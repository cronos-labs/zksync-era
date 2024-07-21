use anyhow::Context as _;
use zksync_config::{
    configs::{wallets, ContractsConfig},
    EthConfig,
};
use zksync_eth_client::clients::{GKMSSigningClient, PKSigningClient};
use zksync_types::L1ChainId;

use crate::{
    implementations::resources::eth_interface::{
        BoundEthInterfaceForBlobsResource, BoundEthInterfaceResource, EthInterfaceResource,
    },
    wiring_layer::{WiringError, WiringLayer},
    FromContext, IntoContext,
};

/// Wiring layer for [`PKSigningClient`].
#[derive(Debug)]
#[non_exhaustive]
pub enum SigningEthClientType {
    PKSigningEthClient,
    GKMSSigningEthClient,
}

#[derive(Debug)]
pub struct PKSigningEthClientLayer {
    eth_sender_config: EthConfig,
    contracts_config: ContractsConfig,
    l1_chain_id: L1ChainId,
    wallets: wallets::EthSender,
    client_type: SigningEthClientType,
}

#[derive(Debug, FromContext)]
#[context(crate = crate)]
pub struct Input {
    pub eth_client: EthInterfaceResource,
}

#[derive(Debug, IntoContext)]
#[context(crate = crate)]
pub struct Output {
    pub signing_client: BoundEthInterfaceResource,
    /// Only provided if the blob operator key is provided to the layer.
    pub signing_client_for_blobs: Option<BoundEthInterfaceForBlobsResource>,
}

impl PKSigningEthClientLayer {
    pub fn new(
        eth_sender_config: EthConfig,
        contracts_config: ContractsConfig,
        l1_chain_id: L1ChainId,
        wallets: wallets::EthSender,
        client_type: SigningEthClientType,
    ) -> Self {
        Self {
            eth_sender_config,
            contracts_config,
            l1_chain_id,
            wallets,
            client_type,
        }
    }
}

#[async_trait::async_trait]
impl WiringLayer for PKSigningEthClientLayer {
    type Input = Input;
    type Output = Output;

    fn layer_name(&self) -> &'static str {
        "pk_signing_eth_client_layer"
    }

    async fn wire(self, input: Self::Input) -> Result<Self::Output, WiringError> {
        let signing_client;
        let mut signing_client_for_blobs = None;

        match self.client_type {
            SigningEthClientType::PKSigningEthClient => {
                let private_key = self.wallets.operator.private_key();
                let gas_adjuster_config = self
                    .eth_sender_config
                    .gas_adjuster
                    .as_ref()
                    .context("gas_adjuster config is missing")?;
                let EthInterfaceResource(query_client) = input.eth_client;

                let sc = PKSigningClient::new_raw(
                    private_key.clone(),
                    self.contracts_config.diamond_proxy_addr,
                    gas_adjuster_config.default_priority_fee_per_gas,
                    self.l1_chain_id,
                    query_client.clone(),
                );
                signing_client = BoundEthInterfaceResource(Box::new(sc));

                signing_client_for_blobs = self.wallets.blob_operator.map(|blob_operator| {
                    let private_key = blob_operator.private_key();
                    let blobs_resources = PKSigningClient::new_raw(
                        private_key.clone(),
                        self.contracts_config.diamond_proxy_addr,
                        gas_adjuster_config.default_priority_fee_per_gas,
                        self.l1_chain_id,
                        query_client,
                    );
                    BoundEthInterfaceForBlobsResource(Box::new(blobs_resources))
                });
            }
            SigningEthClientType::GKMSSigningEthClient => {
                let gas_adjuster_config = self
                    .eth_sender_config
                    .gas_adjuster
                    .as_ref()
                    .context("gas_adjuster config is missing")?;

                let eth_sender_config = self
                    .eth_sender_config
                    .sender
                    .as_ref()
                    .context("eth_sender sender config is missing")?;

                let gkms_op_key_name = &eth_sender_config.gkms_op_key_name;
                tracing::info!("GKMS op key name: {:?}", gkms_op_key_name);

                let EthInterfaceResource(query_client) = input.eth_client;

                let sc = GKMSSigningClient::new_raw(
                    self.contracts_config.diamond_proxy_addr,
                    gas_adjuster_config.default_priority_fee_per_gas,
                    self.l1_chain_id,
                    query_client.clone(),
                    gkms_op_key_name
                        .as_ref()
                        .expect("gkms_op_key_name is required but was None")
                        .to_string(),
                )
                .await;
                signing_client = BoundEthInterfaceResource(Box::new(sc));

                let gkms_op_blob_key_name = &eth_sender_config.gkms_op_blob_key_name;
                tracing::info!("GKMS op blob key name: {:?}", gkms_op_blob_key_name);

                if let Some(key_name) = gkms_op_blob_key_name {
                    let blobs_resources = GKMSSigningClient::new_raw(
                        self.contracts_config.diamond_proxy_addr,
                        gas_adjuster_config.default_priority_fee_per_gas,
                        self.l1_chain_id,
                        query_client,
                        key_name.to_string(),
                    )
                    .await;

                    signing_client_for_blobs =
                        Some(BoundEthInterfaceForBlobsResource(Box::new(blobs_resources)));
                };
            }
        };

        Ok(Output {
            signing_client,
            signing_client_for_blobs,
        })
    }
}
