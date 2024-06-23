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
    service::ServiceContext,
    wiring_layer::{WiringError, WiringLayer},
};

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
    fn layer_name(&self) -> &'static str {
        "pk_signing_eth_client_layer"
    }

    async fn wire(self: Box<Self>, mut context: ServiceContext<'_>) -> Result<(), WiringError> {
        let _signing_client = match self.as_ref().client_type {
            SigningEthClientType::PKSigningEthClient => {
                let private_key = self.wallets.operator.private_key();
                let gas_adjuster_config = self
                    .eth_sender_config
                    .gas_adjuster
                    .as_ref()
                    .context("gas_adjuster config is missing")?;
                let EthInterfaceResource(query_client) = context.get_resource().await?;

                let signing_client = PKSigningClient::new_raw(
                    private_key.clone(),
                    self.contracts_config.diamond_proxy_addr,
                    gas_adjuster_config.default_priority_fee_per_gas,
                    self.l1_chain_id,
                    query_client.clone(),
                );
                context.insert_resource(BoundEthInterfaceResource(Box::new(signing_client)))?;

                if let Some(blob_operator) = &self.wallets.blob_operator {
                    let private_key = blob_operator.private_key();
                    let signing_client_for_blobs = PKSigningClient::new_raw(
                        private_key.clone(),
                        self.contracts_config.diamond_proxy_addr,
                        gas_adjuster_config.default_priority_fee_per_gas,
                        self.l1_chain_id,
                        query_client,
                    );
                    context.insert_resource(BoundEthInterfaceForBlobsResource(Box::new(
                        signing_client_for_blobs,
                    )))?;
                }
            }
            SigningEthClientType::GKMSSigningEthClient => {
                let gas_adjuster_config = self
                    .eth_sender_config
                    .gas_adjuster
                    .as_ref()
                    .context("gas_adjuster config is missing")?;

                let key_name = "projects/zkevm-research/locations/northamerica-northeast2/keyRings/gkms_signer_test/cryptoKeys/gkms_signer_test".to_string();

                let EthInterfaceResource(query_client) = context.get_resource().await?;

                let signing_client = GKMSSigningClient::new_raw(
                    self.contracts_config.diamond_proxy_addr,
                    gas_adjuster_config.default_priority_fee_per_gas,
                    self.l1_chain_id,
                    query_client.clone(),
                    key_name.clone(),
                )
                .await;
                context.insert_resource(BoundEthInterfaceResource(Box::new(signing_client)))?;

                if let Some(_blob_operator) = &self.wallets.blob_operator {
                    let signing_client_for_blobs = GKMSSigningClient::new_raw(
                        self.contracts_config.diamond_proxy_addr,
                        gas_adjuster_config.default_priority_fee_per_gas,
                        self.l1_chain_id,
                        query_client,
                        key_name,
                    )
                    .await;
                    context.insert_resource(BoundEthInterfaceForBlobsResource(Box::new(
                        signing_client_for_blobs,
                    )))?;
                }
            }
        };

        Ok(())
    }
}
