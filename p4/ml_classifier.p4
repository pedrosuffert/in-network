/*
 * P4 ML classifier for UNSW-NB15 (Planter-style).
 * Target: BMv2 v1model.
 */

#include <core.p4>
#include <v1model.p4>

/*************************************************************************
 * CONSTANTS
 *************************************************************************/
const bit<16> TYPE_IPV4 = 0x0800;
const bit<8>  PROTO_TCP = 6;
const bit<8>  PROTO_UDP = 17;

const bit<8> CLASS_NORMAL = 0;
const bit<8> CLASS_ATTACK = 1;

/*************************************************************************
 * HEADERS
 *************************************************************************/
header ethernet_t {
    bit<48> dstAddr;
    bit<48> srcAddr;
    bit<16> etherType;
}

header ipv4_t {
    bit<4>  version;
    bit<4>  ihl;
    bit<8>  diffserv;
    bit<16> totalLen;
    bit<16> identification;
    bit<3>  flags;
    bit<13> fragOffset;
    bit<8>  ttl;
    bit<8>  protocol;
    bit<16> hdrChecksum;
    bit<32> srcAddr;
    bit<32> dstAddr;
}

header tcp_t {
    bit<16> srcPort;
    bit<16> dstPort;
    bit<32> seqNo;
    bit<32> ackNo;
    bit<4>  dataOffset;
    bit<4>  res;
    bit<8>  flags;
    bit<16> window;
    bit<16> checksum;
    bit<16> urgentPtr;
}

header udp_t {
    bit<16> srcPort;
    bit<16> dstPort;
    bit<16> length;
    bit<16> checksum;
}

struct metadata_t {
    bit<1> is_my_mac;
    bit<8> feat_sttl;
    bit<8> feat_sport;
    bit<8> feat_dsport;
    bit<8> feat_sbytes;
    bit<8> feat_dbytes;
    bit<8> code_0;
    bit<8> code_1;
    bit<8> code_2;
    bit<8> ml_class;
    bit<1> classified;
}

struct headers_t {
    ethernet_t ethernet;
    ipv4_t     ipv4;
    tcp_t      tcp;
    udp_t      udp;
}

/*************************************************************************
 * PARSER
 *************************************************************************/
parser MyParser(packet_in packet,
                out headers_t hdr,
                inout metadata_t meta,
                inout standard_metadata_t standard_metadata) {
    
    state start {
        packet.extract(hdr.ethernet);
        transition select(hdr.ethernet.etherType) {
            TYPE_IPV4: parse_ipv4;
            default: accept;
        }
    }
    
    state parse_ipv4 {
        packet.extract(hdr.ipv4);
        transition select(hdr.ipv4.protocol) {
            PROTO_TCP: parse_tcp;
            PROTO_UDP: parse_udp;
            default: accept;
        }
    }
    
    state parse_tcp {
        packet.extract(hdr.tcp);
        transition accept;
    }
    
    state parse_udp {
        packet.extract(hdr.udp);
        transition accept;
    }
}

/*************************************************************************
 * CHECKSUM VERIFICATION
 *************************************************************************/
control MyVerifyChecksum(inout headers_t hdr, inout metadata_t meta) {
    apply { }
}

/*************************************************************************
 * INGRESS - ML Classification
 *************************************************************************/
control MyIngress(inout headers_t hdr,
                  inout metadata_t meta,
                  inout standard_metadata_t standard_metadata) {
    
    action drop() {
        mark_to_drop(standard_metadata);
    }
    
    action forward(bit<9> port) {
        standard_metadata.egress_spec = port;
    }
    
    action set_nhop(bit<48> dst_mac, bit<48> src_mac, bit<9> port) {
        hdr.ethernet.dstAddr = dst_mac;
        hdr.ethernet.srcAddr = src_mac;
        standard_metadata.egress_spec = port;
        hdr.ipv4.ttl = hdr.ipv4.ttl - 1;
    }
    
    action mark_as_my_mac() {
        meta.is_my_mac = 1;
    }

    /* Required on shared Docker bridge: only process packets destined for this switch */
    table my_mac {
        key = { hdr.ethernet.dstAddr: exact; }
        actions = { mark_as_my_mac; drop; }
        size = 8;
        default_action = drop();
    }

    action extract_features() {
        meta.feat_sttl = hdr.ipv4.ttl;
        
        if (hdr.tcp.isValid()) {
            meta.feat_sport = (bit<8>)(hdr.tcp.srcPort[7:0]);
            meta.feat_dsport = (bit<8>)(hdr.tcp.dstPort[7:0]);
        } else if (hdr.udp.isValid()) {
            meta.feat_sport = (bit<8>)(hdr.udp.srcPort[7:0]);
            meta.feat_dsport = (bit<8>)(hdr.udp.dstPort[7:0]);
        }
        
        meta.feat_sbytes = (bit<8>)(hdr.ipv4.totalLen[15:8]);
        meta.feat_dbytes = 0;
    }

    action set_code_0(bit<8> code) { meta.code_0 = code; }
    action set_code_1(bit<8> code) { meta.code_1 = code; }
    action set_code_2(bit<8> code) { meta.code_2 = code; }
    
    table ml_feature_0 {
        key = { meta.feat_sttl: range; }
        actions = { set_code_0; }
        size = 256;
        default_action = set_code_0(0);
    }
    
    table ml_feature_1 {
        key = { meta.feat_sport: range; }
        actions = { set_code_1; }
        size = 256;
        default_action = set_code_1(0);
    }
    
    table ml_feature_2 {
        key = { meta.feat_dsport: range; }
        actions = { set_code_2; }
        size = 256;
        default_action = set_code_2(0);
    }

    action classify(bit<8> ml_class) {
        meta.ml_class = ml_class;
        meta.classified = 1;
    }
    
    table ml_classify {
        key = {
            meta.code_0: exact;
            meta.code_1: exact;
            meta.code_2: exact;
        }
        actions = { classify; }
        size = 4096;
        default_action = classify(CLASS_NORMAL);
    }

    table ipv4_lpm {
        key = { hdr.ipv4.dstAddr: lpm; }
        actions = { set_nhop; drop; }
        size = 1024;
        default_action = drop();
    }
    
    apply {
        meta.is_my_mac = 0;
        my_mac.apply();
        
        if (meta.is_my_mac == 0) {
            drop();
            return;
        }

        if (hdr.ipv4.isValid()) {
            extract_features();
            ml_feature_0.apply();
            ml_feature_1.apply();
            ml_feature_2.apply();
            ml_classify.apply();

            if (meta.ml_class == CLASS_ATTACK) {
                log_msg("ML CLASSIFICATION: ATTACK detected");
                hdr.ipv4.diffserv = 0xFF;
            } else {
                log_msg("ML CLASSIFICATION: Normal traffic");
            }

            if (hdr.ipv4.ttl > 1) {
                ipv4_lpm.apply();
            } else {
                drop();
            }
        }
    }
}

/*************************************************************************
 * EGRESS
 *************************************************************************/
control MyEgress(inout headers_t hdr,
                 inout metadata_t meta,
                 inout standard_metadata_t standard_metadata) {
    apply { }
}

/*************************************************************************
 * CHECKSUM COMPUTATION
 *************************************************************************/
control MyComputeChecksum(inout headers_t hdr, inout metadata_t meta) {
    apply {
        update_checksum(
            hdr.ipv4.isValid(),
            { hdr.ipv4.version, hdr.ipv4.ihl, hdr.ipv4.diffserv,
              hdr.ipv4.totalLen, hdr.ipv4.identification,
              hdr.ipv4.flags, hdr.ipv4.fragOffset, hdr.ipv4.ttl,
              hdr.ipv4.protocol, hdr.ipv4.srcAddr, hdr.ipv4.dstAddr },
            hdr.ipv4.hdrChecksum,
            HashAlgorithm.csum16
        );
    }
}

/*************************************************************************
 * DEPARSER
 *************************************************************************/
control MyDeparser(packet_out packet, in headers_t hdr) {
    apply {
        packet.emit(hdr.ethernet);
        packet.emit(hdr.ipv4);
        packet.emit(hdr.tcp);
        packet.emit(hdr.udp);
    }
}

/*************************************************************************
 * SWITCH
 *************************************************************************/
V1Switch(
    MyParser(),
    MyVerifyChecksum(),
    MyIngress(),
    MyEgress(),
    MyComputeChecksum(),
    MyDeparser()
) main;
