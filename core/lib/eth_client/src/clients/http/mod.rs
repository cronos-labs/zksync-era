use std::time::Duration;

use vise::{
    Buckets, Counter, EncodeLabelSet, EncodeLabelValue, Family, Histogram, LabeledFamily, Metrics,
};

pub use self::signing::{GKMSSigningClient, PKSigningClient, SigningClient};

mod decl;
mod query;
mod signing;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, EncodeLabelValue, EncodeLabelSet)]
#[metrics(label = "method", rename_all = "snake_case")]
enum Method {
    ChainId,
    NonceAtForAccount,
    BlockNumber,
    GetGasPrice,
    SendRawTx,
    BaseFeeHistory,
    #[metrics(name = "get_pending_block_base_fee_per_gas")]
    PendingBlockBaseFee,
    GetTxStatus,
    FailureReason,
    GetTx,
    CallContractFunction,
    TxReceipt,
    EthBalance,
    Logs,
    Block,
    #[metrics(name = "sign_prepared_tx_for_addr")]
    SignPreparedTx,
    Allowance,
    L2FeeHistory,
}

#[derive(Debug, Metrics)]
#[metrics(prefix = "server_ethereum_gateway")]
struct ClientCounters {
    /// Number of calls for a specific Ethereum client method.
    #[metrics(labels = ["method", "component"])]
    call: LabeledFamily<(Method, &'static str), Counter, 2>,
}

#[vise::register]
static COUNTERS: vise::Global<ClientCounters> = vise::Global::new();

#[derive(Debug, Metrics)]
#[metrics(prefix = "eth_client")]
struct ClientLatencies {
    /// Latency of interacting with the Ethereum client.
    #[metrics(buckets = Buckets::LATENCIES)]
    direct: Family<Method, Histogram<Duration>>,
}

#[vise::register]
static LATENCIES: vise::Global<ClientLatencies> = vise::Global::new();
