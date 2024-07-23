use std::collections::HashSet;

use zksync_node_api_server::tx_sender::master_pool_sink::MasterPoolSink;
use zksync_types::Address;

use crate::{
    implementations::resources::{
        pools::{MasterPool, PoolResource},
        web3_api::TxSinkResource,
    },
    wiring_layer::{WiringError, WiringLayer},
    FromContext, IntoContext,
};

/// Wiring layer for [`MasterPoolSink`], [`TxSink`](zksync_node_api_server::tx_sender::tx_sink::TxSink) implementation.
pub struct MasterPoolSinkLayer {
    deny_list: Option<HashSet<Address>>,
}

impl MasterPoolSinkLayer {
    pub fn deny_list(deny_list: Option<HashSet<Address>>) -> Self {
        Self { deny_list }
    }

    pub fn default() -> Self {
        Self { deny_list: None }
    }
}

#[derive(Debug, FromContext)]
#[context(crate = crate)]
pub struct Input {
    pub master_pool: PoolResource<MasterPool>,
}

#[derive(Debug, IntoContext)]
#[context(crate = crate)]
pub struct Output {
    pub tx_sink: TxSinkResource,
}

#[async_trait::async_trait]
impl WiringLayer for MasterPoolSinkLayer {
    type Input = Input;
    type Output = Output;

    fn layer_name(&self) -> &'static str {
        "master_pook_sink_layer"
    }

    async fn wire(self, input: Self::Input) -> Result<Self::Output, WiringError> {
        let pool = input.master_pool.get().await?;
        Ok(Output {
            tx_sink: MasterPoolSink::new(pool, self.deny_list).into(),
        })
    }
}
