#!/bin/bash

current_time="$(date +%Y_%m_%d_%H_%M_%S)"
work_dir=".NodeSpec$current_time"
# 注意：这些URL也已修改，您需要确保它们是实际可用的
bench_os_url="https://github.com/dbedu/NodeSpec/releases/download/v0.0.1/BenchOs.tar.gz"
raw_file_prefix="https://raw.githubusercontent.com/dbedu/NodeSpec/refs/heads/main"

if uname -m | grep -Eq 'arm|aarch64'; then
    bench_os_url="https://github.com/dbedu/NodeSpec/releases/download/v0.0.1/BenchOs-arm.tar.gz"
fi

header_info_filename=header_info.log
basic_info_filename=basic_info.log
yabs_json_filename=yabs.json
ip_quality_filename=ip_quality.log
ip_quality_json_filename=ip_quality.json
net_quality_filename=net_quality.log
net_quality_json_filename=net_quality.json
backroute_trace_filename=backroute_trace.log
backroute_trace_json_filename=backroute_trace.json
port_filename=port.log

function start_ascii(){
    echo -ne "\e[1;36m"
    cat <<- 'EOF'

 ██████   █████              █████           █████████                             
░░██████ ░░███              ░░███           ███░░░░░███                            
 ░███░███ ░███   ██████   ███████   ██████ ░███    ░░░  ████████   ██████   ██████ 
 ░███░░███░███  ███░░███ ███░░███  ███░░███░░█████████ ░░███░░███ ███░░███ ███░░███
 ░███ ░░██████ ░███ ░███░███ ░███ ░███████  ░░░░░░░░███ ░███ ░███░███████ ░███ ░░░ 
 ░███  ░░█████ ░███ ░███░███ ░███ ░███░░░   ███    ░███ ░███ ░███░███░░░  ░███  ███
 █████  ░░█████░░██████ ░░████████░░██████ ░░█████████  ░███████ ░░██████ ░░██████ 
░░░░░    ░░░░░  ░░░░░░   ░░░░░░░░  ░░░░░░   ░░░░░░░░░   ░███░░░   ░░░░░░   ░░░░░░  
                                                        ░███                       
                                                        █████                      
                                                       ░░░░░                       

Benchmark script for server, collects basic hardware information, IP quality and network quality

The benchmark will be performed in a temporary system, and all traces will be deleted after that.
Therefore, it has no impact on the original environment and supports almost all linux systems.

Author: 天道总司
Github: github.com/dbedu/NodeSpec
Command: bash <(curl -sL https://run.NodeSpec.com)

	EOF
    echo -ne "\033[0m"
}

function _red() {
    echo -e "\033[0;31m$1\033[0m"
}

function _yellow() {
    echo -e "\033[0;33m$1\033[0m"
}

function _blue() {
    echo -e "\033[0;36m$1\033[0m"
}

function _green() {
    echo -e "\033[0;32m$1\033[0m"
}

function _red_bold() {
    echo -e "\033[1;31m$1\033[0m"
}

function _yellow_bold() {
    echo -e "\033[1;33m$1\033[0m"
}

function _blue_bold() {
    echo -e "\033[1;36m$1\033[0m"
}

function _green_bold() {
    echo -e "\033[1;32m$1\033[0m"
}



function pre_init(){
    mkdir -p "$work_dir"
    cd $work_dir
    work_dir="$(pwd)"
}

function pre_cleanup(){
    # incase interupted last time
    clear_mount
    if [[ "$work_dir" == *"NodeSpec"* ]]; then
        rm -rf "${work_dir}"/*
    else
        echo "Error: work_dir does not contain 'NodeSpec'!"
        exit 1
    fi
}

function clear_mount(){
    swapoff $work_dir/swap 2>/dev/null

    umount $work_dir/BenchOs/proc/ 2> /dev/null
    umount $work_dir/BenchOs/sys/ 2> /dev/null
    umount -R $work_dir/BenchOs/dev/ 2> /dev/null
}

function load_bench_os(){
    cd $work_dir
    rm -rf BenchOs

    curl "-L#o" BenchOs.tar.gz $bench_os_url
    tar -xzf BenchOs.tar.gz     
    cd $work_dir/BenchOs

    mount -t proc /proc proc/
    mount --bind /sys sys/
    mount --rbind /dev dev/
    mount --make-rslave dev

    rm etc/resolv.conf 2>/dev/null
    cp /etc/resolv.conf etc/resolv.conf
}

function chroot_run(){
    chroot $work_dir/BenchOs /bin/bash -c "$*"
}

function load_part(){
    # gb5-test.sh, swap part
    . <(curl -sL "$raw_file_prefix/part/swap.sh")
}

function load_3rd_program(){
    _blue "Installing necessary tools (jq)..."
    chroot_run apt-get update -y
    chroot_run apt-get install -y jq

    chroot_run wget https://github.com/nxtrace/NTrace-core/releases/download/v1.3.7/nexttrace_linux_amd64 -qO /usr/local/bin/nexttrace
    chroot_run chmod u+x /usr/local/bin/nexttrace
}

function run_header(){
    chroot_run bash <(curl -Ls "$raw_file_prefix/part/header.sh")
}

yabs_url="$raw_file_prefix/part/yabs.sh"
function run_yabs(){
    if ! curl -s 'https://browser.geekbench.com' --connect-timeout 5 >/dev/null; then
        chroot_run bash <(curl -sL $yabs_url) -s -- -gi -w /result/$yabs_json_filename
        echo -e "对 IPv6 单栈的服务器来说进行测试没有意义，\n因为要将结果上传到 browser.geekbench.com 后才能拿到最后的跑分，\n但 browser.geekbench.com 仅有 IPv4、不支持 IPv6，测了也是白测。"
    else
        virt=$(dmidecode -s system-product-name 2> /dev/null || virt-what | grep -v redhat | head -n 1 || echo "none")
        if [[ "${virt,,}" != "lxc" ]]; then
            check_swap 1>&2
        fi
        # 服务器一般测geekbench5即可
        chroot_run bash <(curl -sL $yabs_url) -s -- -5i -w /result/$yabs_json_filename
    fi

    chroot_run bash <(curl -sL $raw_file_prefix/part/sysbench.sh)
}

function run_ip_quality(){
    chroot_run bash <(curl -Ls IP.Check.Place) -n -o /result/$ip_quality_json_filename
}

function run_net_quality(){
    local params=""
    [[ "$run_net_quality_test" =~ ^[Ll]$ ]] && params=" -L"
    chroot_run bash <(curl -Ls Net.Check.Place) $params -n -o /result/$net_quality_json_filename
}

function run_net_trace(){
    chroot_run bash <(curl -Ls Net.Check.Place) -R -n -S 123 -o /result/$backroute_trace_json_filename
}


# ==================================================================
# NEW FUNCTION: Display Parsed Results Locally
# ==================================================================
function display_local_summary(){
    # 定义结果文件路径
    local yabs_json="$result_directory/$yabs_json_filename"
    local ip_json="$result_directory/$ip_quality_json_filename"
    local net_json="$result_directory/$net_quality_json_filename"
    local trace_json="$result_directory/$backroute_trace_json_filename"
    
    _green_bold "========== Server Performance Summary =========="

    # --- 解析和显示系统基本信息 (来自 YABS) ---
    if [ -f "$yabs_json" ]; then
        _yellow_bold "\n[System & CPU Benchmarks]"
        local cpu_model=$(jq -r '.cpu.model' "$yabs_json")
        local geekbench5_score=$(jq -r '.geekbench[] | select(.version==5) | .scores.single' "$yabs_json")
        
        echo "CPU Model          : $cpu_model"
        echo "Geekbench 5 Score  : $geekbench5_score"
    fi

    # --- 解析和显示磁盘性能 (来自 YABS) ---
    if [ -f "$yabs_json" ]; then
        _yellow_bold "\n[Disk Performance]"
        # 提取第一个磁盘测试结果作为代表
        local disk_test=$(jq -r '.disk_tests | to_entries | .[0].value' "$yabs_json")
        local disk_speed_4k=$(echo "$disk_test" | jq -r '.["4k"]')
        local disk_speed_64k=$(echo "$disk_test" | jq -r '.["64k"]')
        local disk_speed_512k=$(echo "$disk_test" | jq -r '.["512k"]')
        
        echo "4K Block Speed     : $disk_speed_4k"
        echo "64K Block Speed    : $disk_speed_64k"
        echo "512K Block Speed   : $disk_speed_512k"
    fi

    # --- 解析和显示IP质量信息 ---
    if [ -f "$ip_json" ]; then
        _yellow_bold "\n[IP Quality Information]"
        local ip=$(jq -r '.ip' "$ip_json")
        local country=$(jq -r '.country_name' "$ip_json")
        local asn=$(jq -r '.asn' "$ip_json")
        local is_hosting=$(jq -r '.hosting' "$ip_json")
        
        echo "IP Address         : $ip"
        echo "Location           : $country"
        echo "ASN                : $asn"
        echo "Is Hosting/Data Center : $is_hosting"
    fi

    # --- 解析和显示网络测速结果 ---
    if [ -f "$net_json" ]; then
        _yellow_bold "\n[Network Speed Test]"
        printf "%-20s | %-15s | %-15s\n" "Location" "Upload Speed" "Download Speed"
        echo "----------------------------------------------------"
        # 使用 jq 循环处理每个测速点
        jq -c '.speedtest[]' "$net_json" | while read -r line; do
            local name=$(echo "$line" | jq -r '.name')
            local upload=$(echo "$line" | jq -r '.upload.speed_formatted')
            local download=$(echo "$line" | jq -r '.download.speed_formatted')
            printf "%-20s | %-15s | %-15s\n" "$name" "$upload" "$download"
        done
    fi

    _green_bold "\n================================================"
    _blue "All tests are complete. Raw data is available in $result_directory"
}


function upload_result(){
    display_local_summary
}

function post_cleanup(){
    echo ""
    read -p "Press [Enter] key to finish and clean up all temporary files..."

    chroot_run umount -R /dev &> /dev/null
    clear_mount

    post_check_mount

    rm -rf $work_dir/BenchOs

    if [[ "$work_dir" == *"NodeSpec"* ]]; then
        rm -rf "${work_dir}"/
    else
        echo "Error: work_dir does not contain 'NodeSpec'!"
        exit 1
    fi

    exit 0
}

function sig_cleanup(){
    trap '' INT TERM SIGHUP EXIT
    _red "Interrupted. Cleaning up immediately..."

    # Perform cleanup actions directly here
    chroot_run umount -R /dev &> /dev/null
    clear_mount
    post_check_mount

    if [[ "$work_dir" == *"NodeSpec"* ]]; then
        rm -rf "${work_dir}"/
    fi

    _red "Cleanup complete."
    exit 1
}

function post_check_mount(){
    if mount | grep NodeSpec$current_time ; then
        echo "出现了预料之外的情况，BenchOs目录的挂载未被清理干净，保险起见请重启后删除该目录" | tee $work_dir/error.log >&2
        exit
    fi
}


function ask_question(){
    yellow='\033[1;33m'  # Set yellow color
    reset='\033[0m'      # Reset to default color

    echo -en "${yellow}Run Basic Info test? (Enter for default 'y') [y/n]: ${reset}"
    read run_yabs_test
    run_yabs_test=${run_yabs_test:-y}

    echo -en "${yellow}Run IPQuality test? (Enter for default 'y') [y/n]: ${reset}"
    read run_ip_quality_test
    run_ip_quality_test=${run_ip_quality_test:-y}

    echo -en "${yellow}Run NetQuality test? (Enter for default 'y', 'l' for low-data mode) [y/l/n]: ${reset}"
    read run_net_quality_test
    run_net_quality_test=${run_net_quality_test:-y}

    echo -en "${yellow}Run Backroute Trace test? (Enter for default 'y') [y/n]: ${reset}"
    read run_net_trace_test
    run_net_trace_test=${run_net_trace_test:-y}

}

function main(){
    trap 'sig_cleanup' INT TERM SIGHUP EXIT

    start_ascii

    ask_question

    _green_bold 'Clean Up before Installation'
    pre_init
    pre_cleanup
    _green_bold 'Load BenchOs'
    load_bench_os

    load_part
    load_3rd_program
    _green_bold 'Basic Info'

    result_directory=$work_dir/BenchOs/result
    mkdir -p $result_directory
    run_header > $result_directory/$header_info_filename

    if [[ "$run_yabs_test" =~ ^[Yy]$ ]]; then
        _green_bold 'Running Basic Info Test...'
        run_yabs | tee $result_directory/$basic_info_filename
    fi

    if [[ "$run_ip_quality_test" =~ ^[Yy]$ ]]; then
        _green_bold 'Running IP Quality Test...'
        run_ip_quality | tee $result_directory/$ip_quality_filename
    fi

    if [[ "$run_net_quality_test" =~ ^[YyLl]$ ]]; then
        _green_bold 'Running Network Quality Test...'
        run_net_quality | tee $result_directory/$net_quality_filename
    fi

    if [[ "$run_net_trace_test" =~ ^[Yy]$ ]]; then
        _green_bold 'Running Backroute Trace...'
        run_net_trace | tee $result_directory/$backroute_trace_filename
    fi

    upload_result
    _green_bold 'Clean Up after Installation'
    post_cleanup
}

main
