use std::{collections::HashSet, fmt};

use anyhow::Context as _;
use async_trait::async_trait;
use tokio::{runtime::Handle, sync::watch};
use zksync_dal::{Connection, ConnectionPool, Core, CoreDal};
use zksync_storage::RocksDB;
use zksync_types::{u256_to_h256, L1BatchNumber, StorageKey, StorageValue, H256};
use zksync_vm_interface::storage::{ReadStorage, StorageSnapshot};

use self::metrics::{SnapshotStage, SNAPSHOT_METRICS};
pub use self::{
    rocksdb_with_memory::{BatchDiff, RocksdbWithMemory},
    snapshot::SnapshotStorage,
};
use crate::{PostgresStorage, RocksdbStorage, RocksdbStorageBuilder, StateKeeperColumnFamily};

mod metrics;
mod rocksdb_with_memory;
mod snapshot;

/// Union of all [`ReadStorage`] implementations that are returned by [`ReadStorageFactory`], such as
/// Postgres- and RocksDB-backed storages.
///
/// Ordinarily, you might want to use the [`OwnedStorage`] type alias instead of using `CommonStorage` directly.
/// The former naming signals that the storage has static lifetime and thus can be sent to Tokio tasks or other threads.
#[derive(Debug)]
pub enum CommonStorage<'a> {
    /// Implementation over a Postgres connection.
    Postgres(PostgresStorage<'a>),
    /// Implementation over a RocksDB cache instance.
    Rocksdb(RocksdbStorage),
    /// Implementation over a RocksDB cache instance with in-memory DB diffs.
    RocksdbWithMemory(RocksdbWithMemory),
    /// In-memory storage snapshot with the Postgres storage fallback.
    Snapshot(SnapshotStorage<'a>),
    /// Generic implementation. Should be used for testing purposes only since it has performance penalty because
    /// of the dynamic dispatch.
    Boxed(Box<dyn ReadStorage + Send + 'a>),
}

impl<'a> CommonStorage<'a> {
    /// Creates a boxed storage. Should be used for testing purposes only.
    pub fn boxed(storage: impl ReadStorage + Send + 'a) -> Self {
        Self::Boxed(Box::new(storage))
    }
}

impl CommonStorage<'static> {
    /// Creates a Postgres-based storage. Because of the `'static` lifetime requirement, `connection` must be
    /// non-transactional.
    ///
    /// # Errors
    ///
    /// Propagates Postgres I/O errors.
    pub async fn postgres(
        mut connection: Connection<'static, Core>,
        l1_batch_number: L1BatchNumber,
    ) -> anyhow::Result<PostgresStorage<'static>> {
        let l2_block_number = if let Some((_, l2_block_number)) = connection
            .blocks_dal()
            .get_l2_block_range_of_l1_batch(l1_batch_number)
            .await?
        {
            l2_block_number
        } else {
            tracing::info!("Could not find latest sealed L2 block, loading from snapshot");
            let snapshot_recovery = connection
                .snapshot_recovery_dal()
                .get_applied_snapshot_status()
                .await?
                .context("Could not find snapshot, no state available")?;
            if snapshot_recovery.l1_batch_number != l1_batch_number {
                anyhow::bail!(
                    "Snapshot contains L1 batch #{} while #{l1_batch_number} was expected",
                    snapshot_recovery.l1_batch_number
                );
            }
            snapshot_recovery.l2_block_number
        };
        tracing::debug!(%l1_batch_number, %l2_block_number, "Using Postgres-based storage");
        PostgresStorage::new_async(Handle::current(), connection, l2_block_number, true).await
    }

    /// Catches up RocksDB synchronously (i.e. assumes the gap is small) and
    /// returns a [`ReadStorage`] implementation backed by caught-up RocksDB.
    ///
    /// # Errors
    ///
    /// Propagates RocksDB and Postgres errors.
    pub async fn rocksdb(
        connection: &mut Connection<'_, Core>,
        rocksdb: RocksDB<StateKeeperColumnFamily>,
        stop_receiver: &watch::Receiver<bool>,
        l1_batch_number: L1BatchNumber,
    ) -> anyhow::Result<Option<Self>> {
        tracing::debug!("Catching up RocksDB synchronously");
        let rocksdb_builder = RocksdbStorageBuilder::from_rocksdb(rocksdb);
        let rocksdb = rocksdb_builder
            .synchronize(connection, stop_receiver, None)
            .await
            .context("Failed to catch up state keeper RocksDB storage to Postgres")?;
        let Some(rocksdb) = rocksdb else {
            tracing::info!("Synchronizing RocksDB interrupted");
            return Ok(None);
        };
        let rocksdb_l1_batch_number = rocksdb
            .l1_batch_number()
            .await
            .ok_or_else(|| anyhow::anyhow!("No L1 batches available in Postgres"))?;
        if l1_batch_number + 1 != rocksdb_l1_batch_number {
            anyhow::bail!(
                "RocksDB synchronized to L1 batch #{} while #{} was expected",
                rocksdb_l1_batch_number,
                l1_batch_number
            );
        }
        tracing::debug!(%rocksdb_l1_batch_number, "Using RocksDB-based storage");
        Ok(Some(rocksdb.into()))
    }

    /// Creates a storage snapshot. Require protective reads to be persisted for the batch, otherwise
    /// will return `Ok(None)`.
    #[tracing::instrument(skip(connection))]
    pub async fn snapshot(
        connection: &mut Connection<'static, Core>,
        l1_batch_number: L1BatchNumber,
    ) -> anyhow::Result<Option<StorageSnapshot>> {
        let latency = SNAPSHOT_METRICS.load_latency[&SnapshotStage::BatchHeader].start();
        let Some(header) = connection
            .blocks_dal()
            .get_l1_batch_header(l1_batch_number)
            .await?
        else {
            return Ok(None);
        };
        let bytecode_hashes: HashSet<_> = header
            .used_contract_hashes
            .into_iter()
            .map(u256_to_h256)
            .collect();
        latency.observe();

        // Check protective reads early on.
        let latency = SNAPSHOT_METRICS.load_latency[&SnapshotStage::ProtectiveReads].start();
        let protective_reads = connection
            .storage_logs_dedup_dal()
            .get_protective_reads_for_l1_batch(l1_batch_number)
            .await?;
        if protective_reads.is_empty() {
            tracing::debug!("No protective reads for batch");
            return Ok(None);
        }
        let protective_reads_len = protective_reads.len();
        let latency = latency.observe();
        tracing::debug!("Loaded {protective_reads_len} protective reads in {latency:?}");

        let latency = SNAPSHOT_METRICS.load_latency[&SnapshotStage::TouchedSlots].start();
        let touched_slots = connection
            .storage_logs_dal()
            .get_touched_slots_for_l1_batch(l1_batch_number)
            .await?;
        let latency = latency.observe();
        tracing::debug!("Loaded {} touched keys in {latency:?}", touched_slots.len());

        let latency = SNAPSHOT_METRICS.load_latency[&SnapshotStage::PreviousValues].start();
        let all_accessed_keys: Vec<_> = protective_reads
            .into_iter()
            .map(|key| key.hashed_key())
            .chain(touched_slots.into_keys())
            .collect();
        let previous_values = connection
            .storage_logs_dal()
            .get_previous_storage_values(&all_accessed_keys, l1_batch_number)
            .await?;
        let latency = latency.observe();
        tracing::debug!(
            "Obtained {} previous values for accessed keys in {latency:?}",
            previous_values.len()
        );

        let latency = SNAPSHOT_METRICS.load_latency[&SnapshotStage::InitialWrites].start();
        let initial_write_info = connection
            .storage_logs_dal()
            .get_l1_batches_and_indices_for_initial_writes(&all_accessed_keys)
            .await?;
        let latency = latency.observe();
        tracing::debug!("Obtained initial write info for accessed keys in {latency:?}");

        let latency = SNAPSHOT_METRICS.load_latency[&SnapshotStage::Bytecodes].start();
        let bytecodes = connection
            .factory_deps_dal()
            .get_factory_deps(&bytecode_hashes)
            .await;
        let latency = latency.observe();
        tracing::debug!(
            "Loaded {} bytecodes used in the batch in {latency:?}",
            bytecodes.len()
        );

        let factory_deps = bytecodes
            .into_iter()
            .map(|(hash_u256, bytes)| (u256_to_h256(hash_u256), bytes))
            .collect();

        let storage = previous_values.into_iter().map(|(key, prev_value)| {
            let prev_value = prev_value.unwrap_or_default();
            let enum_index =
                initial_write_info
                    .get(&key)
                    .copied()
                    .and_then(|(l1_batch, enum_index)| {
                        // Filter out enum indexes assigned "in the future"
                        (l1_batch < l1_batch_number).then_some(enum_index)
                    });
            (key, enum_index.map(|idx| (prev_value, idx)))
        });
        let storage = storage.collect();
        Ok(Some(StorageSnapshot::new(storage, factory_deps)))
    }
}

impl ReadStorage for CommonStorage<'_> {
    fn read_value(&mut self, key: &StorageKey) -> StorageValue {
        match self {
            Self::Postgres(postgres) => postgres.read_value(key),
            Self::Rocksdb(rocksdb) => rocksdb.read_value(key),
            Self::RocksdbWithMemory(rocksdb_mem) => rocksdb_mem.read_value(key),
            Self::Snapshot(snapshot) => snapshot.read_value(key),
            Self::Boxed(storage) => storage.read_value(key),
        }
    }

    fn is_write_initial(&mut self, key: &StorageKey) -> bool {
        match self {
            Self::Postgres(postgres) => postgres.is_write_initial(key),
            Self::Rocksdb(rocksdb) => rocksdb.is_write_initial(key),
            Self::RocksdbWithMemory(rocksdb_mem) => rocksdb_mem.is_write_initial(key),
            Self::Snapshot(snapshot) => snapshot.is_write_initial(key),
            Self::Boxed(storage) => storage.is_write_initial(key),
        }
    }

    fn load_factory_dep(&mut self, hash: H256) -> Option<Vec<u8>> {
        match self {
            Self::Postgres(postgres) => postgres.load_factory_dep(hash),
            Self::Rocksdb(rocksdb) => rocksdb.load_factory_dep(hash),
            Self::RocksdbWithMemory(rocksdb_mem) => rocksdb_mem.load_factory_dep(hash),
            Self::Snapshot(snapshot) => snapshot.load_factory_dep(hash),
            Self::Boxed(storage) => storage.load_factory_dep(hash),
        }
    }

    fn get_enumeration_index(&mut self, key: &StorageKey) -> Option<u64> {
        match self {
            Self::Postgres(postgres) => postgres.get_enumeration_index(key),
            Self::Rocksdb(rocksdb) => rocksdb.get_enumeration_index(key),
            Self::RocksdbWithMemory(rocksdb_mem) => rocksdb_mem.get_enumeration_index(key),
            Self::Snapshot(snapshot) => snapshot.get_enumeration_index(key),
            Self::Boxed(storage) => storage.get_enumeration_index(key),
        }
    }
}

impl<'a> From<PostgresStorage<'a>> for CommonStorage<'a> {
    fn from(value: PostgresStorage<'a>) -> Self {
        Self::Postgres(value)
    }
}

impl From<RocksdbStorage> for CommonStorage<'_> {
    fn from(value: RocksdbStorage) -> Self {
        Self::Rocksdb(value)
    }
}

impl<'a> From<SnapshotStorage<'a>> for CommonStorage<'a> {
    fn from(value: SnapshotStorage<'a>) -> Self {
        Self::Snapshot(value)
    }
}

/// Storage with a static lifetime that can be sent to Tokio tasks etc.
pub type OwnedStorage = CommonStorage<'static>;

/// Factory that can produce storage instances on demand. The storage type is encapsulated as a type param
/// (mostly for testing purposes); the default is [`OwnedStorage`].
#[async_trait]
pub trait ReadStorageFactory<S = OwnedStorage>: fmt::Debug + Send + Sync + 'static {
    /// Creates a storage instance, e.g. over a Postgres connection or a RocksDB instance.
    /// The specific criteria on which one are left up to the implementation.
    ///
    /// Implementations may be cancel-aware and return `Ok(None)` iff `stop_receiver` receives
    /// a stop signal; this is the only case in which `Ok(None)` should be returned.
    async fn access_storage(
        &self,
        stop_receiver: &watch::Receiver<bool>,
        l1_batch_number: L1BatchNumber,
    ) -> anyhow::Result<Option<S>>;
}

/// [`ReadStorageFactory`] producing Postgres-backed storage instances. Hence, it is slower than more advanced
/// alternatives with RocksDB caches and should be used sparingly (e.g., for testing).
#[async_trait]
impl ReadStorageFactory for ConnectionPool<Core> {
    async fn access_storage(
        &self,
        _stop_receiver: &watch::Receiver<bool>,
        l1_batch_number: L1BatchNumber,
    ) -> anyhow::Result<Option<OwnedStorage>> {
        let connection = self.connection().await?;
        let storage = OwnedStorage::postgres(connection, l1_batch_number).await?;
        Ok(Some(storage.into()))
    }
}
