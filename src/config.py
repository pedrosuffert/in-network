"""
Configuration for Planter UNSW-NB15 BMv2 Integration

Place UNSW-NB15 data in:
  - data/raw/UNSW-NB15_*.csv  (raw CSV files)
  - OR data/unsw_nb15.csv     (combined CSV)
"""

from dataclasses import dataclass, field
from pathlib import Path


@dataclass
class Config:
    """Configuration for the Planter pipeline."""

    # Paths (all within this project)
    project_root: Path = field(default_factory=lambda: Path(__file__).resolve().parent.parent)
    data_dir: Path = field(default_factory=lambda: Path(__file__).resolve().parent.parent / "data")
    output_dir: Path = field(default_factory=lambda: Path(__file__).resolve().parent.parent / "generated_p4")

    # Dataset paths (within data_dir)
    unsw_csv_dir: Path | None = None      # data/raw/
    unsw_combined_csv: Path | None = None  # data/unsw_nb15.csv

    # Features for P4 inference (extractable from packet headers)
    p4_features: list = field(default_factory=lambda: [
        "sttl",    # Source TTL - from IP header
        "sport",   # Source port - from TCP/UDP header
        "dsport",  # Destination port - from TCP/UDP header
        "sbytes",  # Source bytes - from counters
        "dbytes",  # Destination bytes - from counters
    ])

    # Model configuration
    max_tree_depth: int = 5  # Limit depth for P4 pipeline stages
    min_samples_leaf: int = 100
    test_size: float = 0.2
    random_state: int = 42

    # Classification mode
    binary_classification: bool = True  # Normal vs Attack

    # Quantization
    quantize_bits: int = 8  # Quantize features to 8-bit (0-255)

    def __post_init__(self):
        """Set up default paths after initialization."""
        # Dataset paths within project (check multiple locations)
        if self.unsw_csv_dir is None:
            # Try NewCSVs first (current structure), then raw
            if (self.data_dir / "NewCSVs").exists():
                self.unsw_csv_dir = self.data_dir / "NewCSVs"
            else:
                self.unsw_csv_dir = self.data_dir / "raw"
        
        if self.unsw_combined_csv is None:
            # Try unsw_results first, then root
            if (self.data_dir / "unsw_results" / "unsw_nb15_combined.csv").exists():
                self.unsw_combined_csv = self.data_dir / "unsw_results" / "unsw_nb15_combined.csv"
            else:
                self.unsw_combined_csv = self.data_dir / "unsw_nb15.csv"

        # Ensure directories exist
        self.data_dir.mkdir(parents=True, exist_ok=True)
        self.output_dir.mkdir(parents=True, exist_ok=True)


# UNSW-NB15 column names (49 features)
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
