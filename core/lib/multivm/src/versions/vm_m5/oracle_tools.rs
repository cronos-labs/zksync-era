use std::fmt::Debug;

use zk_evm_1_3_1::witness_trace::DummyTracer;

use crate::vm_m5::{
    event_sink::InMemoryEventSink,
    memory::SimpleMemory,
    oracles::{
        decommitter::DecommitterOracle, precompile::PrecompilesProcessorWithHistory,
        storage::StorageOracle,
    },
    storage::{Storage, StoragePtr},
    vm_instance::MultiVmSubversion,
};

#[derive(Debug)]
pub struct OracleTools<const B: bool, S: Storage> {
    pub storage: StorageOracle<S>,
    pub memory: SimpleMemory,
    pub event_sink: InMemoryEventSink,
    pub precompiles_processor: PrecompilesProcessorWithHistory<B>,
    pub decommittment_processor: DecommitterOracle<S, B>,
    pub witness_tracer: DummyTracer,
    pub storage_view: StoragePtr<S>,
}

impl<S: Storage> OracleTools<false, S> {
    pub fn new(storage_pointer: StoragePtr<S>, refund_state: MultiVmSubversion) -> Self {
        Self {
            storage: StorageOracle::new(storage_pointer.clone(), refund_state),
            memory: SimpleMemory::default(),
            event_sink: InMemoryEventSink::default(),
            precompiles_processor: PrecompilesProcessorWithHistory::default(),
            decommittment_processor: DecommitterOracle::new(storage_pointer.clone()),
            witness_tracer: DummyTracer {},
            storage_view: storage_pointer,
        }
    }
}
