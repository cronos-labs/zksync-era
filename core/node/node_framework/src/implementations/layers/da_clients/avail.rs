use google_cloud_kms::{
    client::{Client as kms_client, ClientConfig as kms_config},
    grpc::kms::v1::DecryptRequest,
};
use google_cloud_storage::{
    client::{Client as storage_client, ClientConfig as storage_config},
    http::objects::{download::Range, get::GetObjectRequest},
};
use hex;
use tokio;
use zksync_config::AvailConfig;
use zksync_da_client::DataAvailabilityClient;
use zksync_da_clients::avail::AvailClient;

use crate::{
    implementations::resources::da_client::DAClientResource,
    wiring_layer::{WiringError, WiringLayer},
    IntoContext,
};

#[derive(Debug)]
pub struct AvailWiringLayer {
    config: AvailConfig,
}

impl AvailWiringLayer {
    pub fn new(config: AvailConfig) -> Self {
        Self { config }
    }

    pub fn new_with_google_cloud(config: AvailConfig) -> Self {
        // Makes sure that `rustls` crypto backend is set before we instantiate
        // a `Web3` client. `jsonrpsee` doesn't explicitly set it, and when
        // multiple crypto backends are enabled, `rustls` can't choose one and panics.
        // See [this issue](https://github.com/rustls/rustls/issues/1877) for more detail.
        let _ = rustls::crypto::aws_lc_rs::default_provider().install_default();
        
        let rt = tokio::runtime::Runtime::new().unwrap();

        // Download encryped seed for google cloud storage
        let encrypted_seed = rt.block_on(Self::download_seed_from_gcs());

        // Decrypt seed with kms key
        let decrypted_seed = rt.block_on(Self::decrypt_seed_with_kms(&encrypted_seed));

        let mut config_with_gcs_seed = config;
        config_with_gcs_seed.seed = decrypted_seed;

        Self::new(config_with_gcs_seed)
    }

    async fn decrypt_seed_with_kms(encrypted_seed: &[u8]) -> String {
        let config = kms_config::default().with_auth().await.unwrap();
        let client = kms_client::new(config).await.unwrap();

        let avail_seed_key_name = std::env::var("GOOGLE_KMS_AVAIL_SEED_KEY_NAME")
            .expect("Failed to get avail seed key name");
        tracing::info!("Avail seed key name: {:?}", avail_seed_key_name);

        let request = DecryptRequest {
            name: avail_seed_key_name,
            ciphertext: encrypted_seed.to_vec(),
            additional_authenticated_data: vec![],
            ciphertext_crc32c: None,
            additional_authenticated_data_crc32c: None,
        };

        let decrypted_seed = client
            .decrypt(request, None)
            .await
            .expect("Failed to decrypt seed");

        hex::encode(decrypted_seed.plaintext)
    }

    // Downloads the seed from the specified GCS bucket.
    async fn download_seed_from_gcs() -> Vec<u8> {
        let config = storage_config::default().with_auth().await.unwrap();
        let client = storage_client::new(config);

        let avail_bucket_name = std::env::var("GOOGLE_STORAGE_AVAIL_BUCKET_NAME")
            .expect("Failed to get avail bucket name");
        tracing::info!("Avail bucket name: {:?}", avail_bucket_name);

        // Download the file
        client
            .download_object(
                &GetObjectRequest {
                    bucket: avail_bucket_name,
                    object: "seed.bin".to_string(),
                    ..Default::default()
                },
                &Range::default(),
            )
            .await
            .unwrap()
    }
}

#[derive(Debug, IntoContext)]
#[context(crate = crate)]
pub struct Output {
    pub client: DAClientResource,
}

#[async_trait::async_trait]
impl WiringLayer for AvailWiringLayer {
    type Input = ();
    type Output = Output;

    fn layer_name(&self) -> &'static str {
        "avail_client_layer"
    }

    async fn wire(self, _input: Self::Input) -> Result<Self::Output, WiringError> {
        let client: Box<dyn DataAvailabilityClient> =
            Box::new(AvailClient::new(self.config).await?);

        Ok(Self::Output {
            client: DAClientResource(client),
        })
    }
}
