#!/bin/bash

# 清理已有配置（防止冲突）
ip netns delete ns1 2>/dev/null
ip netns delete ns2 2>/dev/null
for i in {1..8}; do
    ip link delete veth1-$i 2>/dev/null
    ip link delete veth2-$i 2>/dev/null
done

# 创建网络命名空间
ip netns add ns1
ip netns add ns2

# 启用MPTCP（确保内核支持）
sysctl -w net.mptcp.enabled=1

# 创建veth对并配置网络
for i in {1..8}; do
    # 创建veth对
    ip link add veth1-$i type veth peer name veth2-$i
    
    # 将接口放入命名空间
    ip link set veth1-$i netns ns1
    ip link set veth2-$i netns ns2
    
    # 配置IP地址（不同子网段）
    ip netns exec ns1 ip addr add 10.10.$i.1/24 dev veth1-$i
    ip netns exec ns2 ip addr add 10.10.$i.2/24 dev veth2-$i

    tc -n ns1 qdisc add dev veth1-$i root netem rate 100mbit
    tc -n ns2 qdisc add dev veth2-$i root netem rate 100mbit
    # 启用接口
    ip netns exec ns1 ip link set veth1-$i up
    ip netns exec ns2 ip link set veth2-$i up
    
    # 为每个接口添加MPTCP端点（signal模式）
    ip netns exec ns1 ip mptcp limits set subflows 8 add_addr_accepted 8
    ip netns exec ns1 ip mptcp endpoint add "10.10.$i.1" dev veth1-$i id $i signal

    ip netns exec ns2 ip mptcp limits set subflows 8 add_addr_accepted 8
    ip netns exec ns2 ip mptcp endpoint add "10.10.$i.2" dev veth2-$i id $i subflow
done

# 在ns1中启动iperf3服务器
echo "Starting iperf3 server in ns1..."
ip netns exec ns1 iperf3 -s &

# 在ns2中运行客户端测试（测试所有路径）
echo "Running iperf3 client in ns2..."
ip netns exec ns2 iperf3 -c 10.10.1.1

#清理环境（取消注释以下行以自动清理）
ip netns delete ns1
ip netns delete ns2
for i in {1..8}; do
    ip link delete veth1-$i 2>/dev/null
    ip link delete veth2-$i 2>/dev/null
done

