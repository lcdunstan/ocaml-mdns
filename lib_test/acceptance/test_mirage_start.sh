#!/bin/bash
set -e
set -x

original_pwd=$PWD
. config.sh
. common.sh
need_root

if [ ! -d $tmp_here ] ; then
    mkdir $tmp_here
fi

echo "Build the unikernel"
chown $normal_user:$normal_user $tmp_here
(cd $tmp_here && sudo -u $normal_user ../mbuild.sh)

# Generate the XL configuration
mirage_xl=$tmp_here/$mirage_name.xl
cat <<EOF > $mirage_xl
name = '$mirage_name'
kernel = '${PWD}/$tmp_here/mir-$mirage_name.xen'
builder = 'linux'
memory = 16
on_crash = 'preserve'

vif = ['bridge=${bridge},mac=${mirage_mac}' ]
EOF
chown $normal_user:$normal_user $mirage_xl

# Start a packet capture
cap_file=$tmp_here/test_mirage_start.pcap
#cap_out=$tmp_here/test_mirage_start.log
cap_out=/dev/null
if [ -f $cap_file ] ; then
    rm $cap_file
fi
echo "Starting packet capture"
tcpdump -q -i $bridge -w $cap_file > $cap_out 2>&1 &
cap_pid=$!
#echo "tcpdump PID: $cap_pid"

echo "Starting unikernel"
xl create $mirage_xl
# Wait for it to respond to pings
wait_ping $mirage_ipaddr 10

echo "Delaying..."
sleep 10

# Kill the unikernel
echo "Stopping unikernel"
xl destroy $mirage_name
# Stop the packet capture (Ctrl+C)
kill -INT $cap_pid
wait $cap_pid
chown $normal_user:$normal_user $cap_file

# Convert the pcap to text
# -ttttt enables relative timestamps
# udp filters out the ICMP and ARP packets
cap_txt=$tmp_here/test_mirage_start.txt
tcpdump -r $cap_file -ttttt -vvv udp and not ether host $bridge_mac > $cap_txt 2> /dev/null
chown $normal_user:$normal_user $cap_txt

./verify_mirage_start.py < $cap_txt > $tmp_here/verify_mirage_start.txt
diff -u verify_mirage_start.txt $tmp_here/verify_mirage_start.txt

