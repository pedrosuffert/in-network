"""Config for Planter UNSW-NB15 BMv2 integration.

Data locations (checked in order):
  - data/unsw_results/unsw_nb15_combined.csv
  - data/unsw_nb15.csv
  - data/NewCSVs/UNSW-NB15_*.csv or data/raw/UNSW-NB15_*.csv
"""

from dataclasses import dataclass, field
from pathlib import Path


@dataclass
class Config:
    """Planter pipeline settings."""

    project_root: Path = field(default_factory=lambda: Path(__file__).resolve().parent.parent)
    data_dir: Path = field(default_factory=lambda: Path(__file__).resolve().parent.parent / "data")
    output_dir: Path = field(default_factory=lambda: Path(__file__).resolve().parent.parent / "generated_p4")

    unsw_csv_dir: Path | None = None
    unsw_combined_csv: Path | None = None

    # Must be extractable from packet headers (IP/TCP/UDP)
    p4_features: list = field(default_factory=lambda: [
        "sttl", "sport", "dsport", "sbytes", "dbytes",
    ])

    max_tree_depth: int = 5   # P4 pipeline stage limit
    min_samples_leaf: int = 100
    test_size: float = 0.2
    random_state: int = 42

    binary_classification: bool = True
    quantize_bits: int = 8

    def __post_init__(self):
        if self.unsw_csv_dir is None:
            self.unsw_csv_dir = self.data_dir / "NewCSVs" if (self.data_dir / "NewCSVs").exists() else self.data_dir / "raw"

        if self.unsw_combined_csv is None:
            combined = self.data_dir / "unsw_results" / "unsw_nb15_combined.csv"
            self.unsw_combined_csv = combined if combined.exists() else self.data_dir / "unsw_nb15.csv"

        self.data_dir.mkdir(parents=True, exist_ok=True)
        self.output_dir.mkdir(parents=True, exist_ok=True)


# UNSW-NB15 schema (49 columns)
UNSW_COLUMNS = [
    "srcip", "sport", "dstip", "dsport", "proto", "state", "dur", "sbytes",
    "dbytes", "sttl", "dttl", "sloss", "dloss", "service", "Sload", "Dload",
    "Spkts", "Dpkts", "swin", "dwin", "stcpb", "dtcpb", "smeansz", "dmeansz",
    "trans_depth", "res_bdy_len", "Sjit", "Djit", "Stime", "Ltime", "Sintpkt",
    "Dintpkt", "tcprtt", "synack", "ackdat", "is_sm_ips_ports", "ct_state_ttl",
    "ct_flw_http_mthd", "is_ftp_login", "ct_ftp_cmd", "ct_srv_src", "ct_srv_dst",
    "ct_dst_ltm", "ct_src_ltm", "ct_src_dport_ltm", "ct_dst_sport_ltm",
    "ct_dst_src_ltm", "attack_cat", "Label",
]
