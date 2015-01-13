tmp_here=tmp
normal_user=mirage

bridge=brtest
bridge_mac=c0:ff:ee:00:00:01
bridge_ipaddr=192.168.3.1

linux_guest_name=ubuntu-guest
linux_guest_kernel=/root/dom0_kernel
linux_guest_mac=c0:ff:ee:00:00:03
linux_guest_ipaddr=192.168.3.2
linux_guest_disk=/dev/vg0/linux-guest

mirage_name=mdns-resp-test
mirage_xen=../mirage/mir-mdns-resp-test.xen
mirage_mac=c0:ff:ee:00:00:02
mirage_ipaddr=192.168.3.3
