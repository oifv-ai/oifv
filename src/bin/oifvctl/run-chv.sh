# The MAC address must be attached to the macvtap and be used inside the guest
# Host network adapter to bridge the guest onto
host_net="eno1"
disk_img="${HOME}"/debian_disk.raw
kernel_img="${HOME}"/hypervisor-fw

###
# TODO(sdake)Cleanup the mess from prior runs. Ya, should
# be running post-exit. compromises.

sudo ip link delete link "$host_net" name macvtap0
oifv_fs_sock="${HOME}"/oifv_fs.sock
oifv_pid="${HOME}"/oifv_fs.pid
oifv_api_sock="${HOME}"/oifv.sock
oifv_vsock="${HOME}"/oifv.vsock
oifv_log="${HOME}"/oifv.log
oifv_net_sock="${HOME}"/oifv_net.sock
rm -f "${oifv_fs_sock}"
rm -f "${oifv_pid}"
rm -f "${oifv_api_sock}"
rm -f "${oifv_vsock}"
rm -f "${oifv_log}"
rm -f "${oifv_net_sock}"

###
# This device may not be hairpinned, so you will need to login
# to this node from a host not running the hypervisor

echo "Creating bridged network device to eno1"
sudo driverctl set-override 0000:d8:00.0 vfio-pci
sudo ip link delete link "${host_net}" name macvtap0

###
# Create a macvtap in bridge mode on the host network

sudo ip link add link "${host_net}" name macvtap0 type macvtap mode bridge
sudo ip link set macvtap0 up
sudo ip link show macvtap0


###
# A new character device is created for this interface

mac="$(cat /sys/class/net/macvtap0/address)"
ifindex="$(cat /sys/class/net/macvtap0/ifindex)"
tapdevice=/dev/tap"${ifindex}"

echo "Mac=${mac} ifindex=${ifindex} tapdevice=${tapdevice}"

# Ensure that we can access this device
sudo chown "$UID.$UID" "$tapdevice"

###
# Share $HOME/repos

virtiofsd \
    --socket-path="${oifv_fs_sock}" \
    --shared-dir=${HOME}/repos \
    --cache=never \
    --thread-pool-size=4 &

###
# Start hypervisor

cloud-hypervisor \
	--api-socket "${oifv_api_sock}" \
	--kernel "${kernel_img}" \
	--disk path="${disk_img}" \
	--serial tty \
	--console pty \
        --cmdline "module_blacklist=nouveau,nvidiafb root=/dev/vda1 rw" \
	--cpus "boot=64" \
	--memory "size=64G,hugepages=on,shared=on,hugepage_size=2M" \
	--net fd=3,mac="${mac}",num_queues=2,queue_size=1024,vhost_user=true,vhost_mode=server,socket="${oifv_net_sock}" 3<>"${tapdevice}" \
	-v \
	--fs tag=homefs,socket="${oifv_fs_sock}",num_queues=1,queue_size=1024 \
	--vsock cid=3,socket="${oifv_vsock}" \
	--log-file "${oifv_log}" \
	--device path="/sys/bus/pci/devices/0000:5e:00.0" \
		path="/sys/bus/pci/devices/0000:d8:00.0" &

###
# UGH - portions of the startup process are extremely clunky. Here is
# TODO(sdake) a prime example.

sleep 2

###
# Start vhost_user_net networking

vhost_user_net --net-backend ip=192.168.33.63,mask=255.255.255.0,socket="${oifv_net_sock}",client=on,num_queues=2,queue_size=1024
