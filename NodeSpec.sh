#!/bin/bash
SCRIPT_VERSION="1.0.0"
EXEC_DIR=$(pwd)
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
    _blue "Installing necessary tools (jq, ca-certificates, unzip, dmidecode)..."
    # 隐藏 apt-get update 的输出
    chroot_run apt-get update -y > /dev/null 2>&1
    # 隐藏 apt-get install 的输出
    chroot_run apt-get install -y jq ca-certificates unzip dmidecode > /dev/null 2>&1
    
    _green "Dependencies installed successfully." # 可以增加一句成功提示

    chroot_run wget https://github.com/nxtrace/NTrace-core/releases/download/v1.3.7/nexttrace_linux_amd64 -qO /usr/local/bin/nexttrace
    chroot_run chmod u+x /usr/local/bin/nexttrace
}

function run_header(){
    chroot_run bash <(curl -Ls "$raw_file_prefix/part/header.sh")
}

yabs_url="$raw_file_prefix/part/yabs.sh"
function run_yabs(){
    _blue "Downloading YABS script..."
    chroot_run curl -sL "$yabs_url" -o "/tmp/yabs.sh"

    if ! chroot_run [ -s "/tmp/yabs.sh" ]; then
        _red_bold "Error: Failed to download yabs.sh script. Aborting YABS test."
        return 1
    fi

    _blue "Executing YABS script..."

    # 构建 YABS 参数
    # -i : 跳过 iperf 网络测试
    # -j : 将 JSON 结果打印到标准输出
    # -w : 将 JSON 结果写入文件
    # -5 : 明确指定运行 Geekbench 5
    local yabs_params="-i -w /result/$yabs_json_filename -5"

    if ! curl -s 'https://browser.geekbench.com' --connect-timeout 5 >/dev/null; then
        # IPv6-only 环境 (YABS 的 -g 标志会跳过所有 Geekbench 测试)
        chroot_run bash /tmp/yabs.sh -g -i -w /result/$yabs_json_filename
        echo -e "对 IPv6 单栈的服务器来说进行测试没有意义，因为无法连接 Geekbench。"
    else
        # IPv4 or Dual Stack 环境
        virt=$(dmidecode -s system-product-name 2> /dev/null || virt-what | grep -v redhat | head -n 1 || echo "none")
        if [[ "${virt,,}" != "lxc" ]]; then
            check_swap 1>&2
        fi
        chroot_run bash /tmp/yabs.sh $yabs_params
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
# FINALIZED FUNCTION: Generate and Display Final Report in TXT and MD
# ==================================================================
function generate_final_report(){
    _green_bold "\n========== Generating Final Report =========="

    # Define paths for source JSON files (relative to chroot)
    local yabs_json_chroot="/result/$yabs_json_filename"
    local ip_json_chroot="/result/$ip_quality_json_filename"
    local net_json_chroot="/result/$net_quality_json_filename"
    local trace_log_chroot="/result/$backroute_trace_log"

    # Define paths for the final report files on the host
    local text_report_path="$EXEC_DIR/NodeSpec-Report-$current_time.txt"
    local md_report_path="$EXEC_DIR/NodeSpec-Report-$current_time.md"

    # --- Create empty report files ---
    > "$text_report_path"
    > "$md_report_path"

    # --- Header ---
    local test_time=$(date +"%Y-%m-%d %H:%M:%S")
    echo "NodeSpec v${SCRIPT_VERSION} -- https://github.com/dbedu/NodeSpec" | tee -a "$text_report_path"
    echo "Test Time: $test_time" | tee -a "$text_report_path"
    # MD Header
    echo "### NodeSpec v${SCRIPT_VERSION} Report" >> "$md_report_path"
    echo "**Test Time:** $test_time" >> "$md_report_path"


    # --- System Information ---
    if chroot_run [ -f "$yabs_json_chroot" ]; then
        # Extract data into variables first
        local os=$(chroot_run "jq -r '.os.distro' $yabs_json_chroot")
        local arch=$(chroot_run "jq -r '.os.arch' $yabs_json_chroot")
        local kernel=$(chroot_run "jq -r '.os.kernel' $yabs_json_chroot")
        local cpu_model=$(chroot_run "jq -r '.cpu.model' $yabs_json_chroot")
        local cpu_cores=$(chroot_run "jq -r '.cpu.cores' $yabs_json_chroot")
        local ram_kb=$(chroot_run "jq -r '.mem.ram' $yabs_json_chroot")
        local swap_kb=$(chroot_run "jq -r '.mem.swap' $yabs_json_chroot")
        local disk_kb=$(chroot_run "jq -r '.mem.disk' $yabs_json_chroot")
        # Format RAM/Swap/Disk into MiB/GiB
        local ram=$(awk -v kb="$ram_kb" 'BEGIN{printf "%.0f MiB", kb/1024}')
        local swap=$(awk -v kb="$swap_kb" 'BEGIN{printf "%.0f MiB", kb/1024}')
        local disk=$(awk -v kb="$disk_kb" 'BEGIN{printf "%.1f GiB", kb/1024/1024}')

        # TXT Output
        {
            echo -e "\n--- System Information ---"
            printf "%-12s: %s (%s)\n" "OS" "$os" "$arch"
            printf "%-12s: %s\n" "Kernel" "$kernel"
            printf "%-12s: %s (%s Cores)\n" "CPU Model" "$cpu_model" "$cpu_cores"
            printf "%-12s: %s\n" "RAM" "$ram"
            printf "%-12s: %s\n" "Swap" "$swap"
            printf "%-12s: %s\n" "Disk" "$disk"
        } | tee -a "$text_report_path"
        
        # MD Output
        {
            echo -e "\n### System Information\n"
            echo "| Item | Details |"
            echo "|:---|:---|"
            echo "| **OS** | $os ($arch) |"
            echo "| **Kernel** | $kernel |"
            echo "| **CPU Model** | $cpu_model ($cpu_cores Cores) |"
            echo "| **RAM** | $ram |"
            echo "| **Swap** | $swap |"
            echo "| **Disk** | $disk |"
        } >> "$md_report_path"
    fi

    # --- Geekbench ---
    if chroot_run [ -f "$yabs_json_chroot" ]; then
        local gb_version=$(chroot_run "jq -r '.geekbench[0].version // \"N/A\"' $yabs_json_chroot")
        if [[ "$gb_version" != "N/A" ]]; then
            local gb_single=$(chroot_run "jq -r '.geekbench[0].single' $yabs_json_chroot")
            local gb_multi=$(chroot_run "jq -r '.geekbench[0].multi' $yabs_json_chroot")
            local gb_url=$(chroot_run "jq -r '.geekbench[0].url' $yabs_json_chroot")

            # TXT Output
            {
                echo -e "\n--- Geekbench v${gb_version} CPU Benchmark ---"
                printf "%-12s: %s\n" "Single-Core" "$gb_single"
                printf "%-12s: %s\n" "Multi-Core" "$gb_multi"
                printf "%-12s: %s\n" "Full Report" "$gb_url"
            } | tee -a "$text_report_path"

            # MD Output
            {
                echo -e "\n### Geekbench v${gb_version} CPU Benchmark\n"
                echo "| Test | Score |"
                echo "|:---|:---|"
                echo "| **Single-Core** | $gb_single |"
                echo "| **Multi-Core** | $gb_multi |"
                echo "| **Full Report** | [View Online]($gb_url) |"
            } >> "$md_report_path"
        fi
    fi

    # --- FIO Disk I/O ---
    if chroot_run [ -f "$yabs_json_chroot" ]; then
        # TXT Output
        {
            echo -e "\n--- FIO Disk I/O Benchmark (Mixed R/W) ---"
            printf "%-12s | %-20s | %-20s | %-20s\n" "Block Size" "Read" "Write" "Total"
            printf -- '-%.0s' {1..70} && echo "" 
        } | tee -a "$text_report_path"

        # MD Output
        {
            echo -e "\n### FIO Disk I/O Benchmark (Mixed R/W)\n"
            echo "| Block Size | Read | Write | Total |"
            echo "|:---|:---|:---|:---|"
        } >> "$md_report_path"

        chroot_run "jq -c '.fio[]' $yabs_json_chroot" | while read -r line; do
            local bs=$(echo "$line" | jq -r '.bs')
            local r_kbps=$(echo "$line" | jq -r '.speed_r')
            local w_kbps=$(echo "$line" | jq -r '.speed_w')
            local t_kbps=$(echo "$line" | jq -r '.speed_rw')
            local r_iops=$(echo "$line" | jq -r '.iops_r')
            local w_iops=$(echo "$line" | jq -r '.iops_w')
            local t_iops=$(echo "$line" | jq -r '.iops_rw')
            
            # Format speeds and iops
            local read_f=$(awk -v kbps="$r_kbps" -v iops="$r_iops" 'BEGIN{ if(kbps > 1000*1000) {printf "%.2f GB/s", kbps/1000/1000} else {printf "%.2f MB/s", kbps/1000}; printf " (%s IOPS)", iops}')
            local write_f=$(awk -v kbps="$w_kbps" -v iops="$w_iops" 'BEGIN{ if(kbps > 1000*1000) {printf "%.2f GB/s", kbps/1000/1000} else {printf "%.2f MB/s", kbps/1000}; printf " (%s IOPS)", iops}')
            local total_f=$(awk -v kbps="$t_kbps" -v iops="$t_iops" 'BEGIN{ if(kbps > 1000*1000) {printf "%.2f GB/s", kbps/1000/1000} else {printf "%.2f MB/s", kbps/1000}; printf " (%s IOPS)", iops}')

            # TXT Output
            printf "%-12s | %-20s | %-20s | %-20s\n" "$bs" "$read_f" "$write_f" "$total_f" | tee -a "$text_report_path"
            # MD Output
            echo "| **$bs** | $read_f | $write_f | $total_f |" >> "$md_report_path"
        done
    fi

    # --- IP Quality ---
    if chroot_run [ -f "$ip_json_chroot" ]; then
        local ip=$(chroot_run "jq -r '.ip' $ip_json_chroot")
        local country=$(chroot_run "jq -r '.country' $ip_json_chroot")
        local city=$(chroot_run "jq -r '.city' $ip_json_chroot")
        local region=$(chroot_run "jq -r '.region' $ip_json_chroot")
        local asn=$(chroot_run "jq -r '.asn' $ip_json_chroot")
        local isp=$(chroot_run "jq -r '.isp' $ip_json_chroot")
        local is_hosting=$(chroot_run "jq -r '.hosting' $ip_json_chroot")
        local is_vpn=$(chroot_run "jq -r '.vpn' $ip_json_chroot")
        local is_proxy=$(chroot_run "jq -r '.proxy' $ip_json_chroot")
        
        local ip_type=""
        [ "$is_hosting" = "true" ] && ip_type+="Hosting/Datacenter "
        [ "$is_vpn" = "true" ] && ip_type+="VPN "
        [ "$is_proxy" = "true" ] && ip_type+="Proxy "
        [ -z "$ip_type" ] && ip_type="Residential/Mobile"

        # TXT Output
        {
            echo -e "\n--- IP Quality & Geolocation ---"
            printf "%-12s: %s\n" "IP Address" "$ip"
            printf "%-12s: %s, %s, %s\n" "Location" "$city" "$region" "$country"
            printf "%-12s: %s\n" "ASN" "$asn"
            printf "%-12s: %s\n" "ISP" "$isp"
            printf "%-12s: %s\n" "IP Type" "$ip_type"
        } | tee -a "$text_report_path"

        # MD Output
        {
            echo -e "\n### IP Quality & Geolocation\n"
            echo "| Item | Details |"
            echo "|:---|:---|"
            echo "| **IP Address** | $ip |"
            echo "| **Location** | $city, $region, $country |"
            echo "| **ASN** | $asn |"
            echo "| **ISP** | $isp |"
            echo "| **IP Type** | $ip_type |"
        } >> "$md_report_path"
    fi
    
    # --- Network Performance ---
    if chroot_run [ -f "$net_json_chroot" ]; then
         # TXT Output
        {
            echo -e "\n--- Network Performance (iperf3) ---"
            printf "%-28s | %-18s | %-18s\n" "Node Location" "Upload Speed" "Download Speed"
            printf -- '-%.0s' {1..70} && echo ""
        } | tee -a "$text_report_path"

        # MD Output
        {
            echo -e "\n### Network Performance (iperf3)\n"
            echo "| Node Location | Upload Speed | Download Speed |"
            echo "|:---|:---|:---|"
        } >> "$md_report_path"

        chroot_run "jq -c '.speedtest[]' $net_json_chroot" | while read -r line; do
            local name=$(echo "$line" | jq -r '.name')
            local upload=$(echo "$line" | jq -r '.upload.speed_formatted')
            local download=$(echo "$line" | jq -r '.download.speed_formatted')
            
            # TXT Output
            printf "%-28s | %-18s | %-18s\n" "$name" "$upload" "$download" | tee -a "$text_report_path"
            # MD Output
            echo "| $name | $upload | $download |" >> "$md_report_path"
        done
    fi

    # --- Backroute Trace ---
    if chroot_run [ -f "$trace_log_chroot" ]; then
        # TXT Output
        {
            echo -e "\n--- Backroute Trace ---" 
            chroot_run "awk '/Backroute Trace/,/=====/' $trace_log_chroot"
        } | tee -a "$text_report_path"

        # MD Output
        {
            echo -e "\n### Backroute Trace\n"
            echo '```text'
            chroot_run "awk '/Backroute Trace/,/=====/' $trace_log_chroot"
            echo '```'
        } >> "$md_report_path"
    fi

    # Final Display
    echo -e "\n\n"
    _green_bold "================================================="
    _green_bold "         COMPLETE SERVER REPORT (Terminal)"
    _green_bold "=================================================\n"
    cat "$text_report_path"
    _green_bold "\n================================================="
    _blue "A copy of this report has been saved to:"
    _yellow "$text_report_path"
    _blue "A beautiful Markdown version has been saved to:"
    _yellow "$md_report_path"
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
        run_yabs 2>&1 | tee $result_directory/$basic_info_filename
    fi

    if [[ "$run_ip_quality_test" =~ ^[Yy]$ ]]; then
        _green_bold 'Running IP Quality Test...'
        run_ip_quality 2>&1 | tee $result_directory/$ip_quality_filename
    fi

    if [[ "$run_net_quality_test" =~ ^[YyLl]$ ]]; then
        _green_bold 'Running Network Quality Test...'
        run_net_quality 2>&1 | tee $result_directory/$net_quality_filename
    fi

    if [[ "$run_net_trace_test" =~ ^[Yy]$ ]]; then
        _green_bold 'Running Backroute Trace...'
        run_net_trace 2>&1 | tee $result_directory/$backroute_trace_filename
    fi

    generate_final_report
    _green_bold 'Clean Up after Installation'
    post_cleanup
}

main
