
function dom_exists {
    domname=$1
    if xl domid "$domname" > /dev/null 2>&1 ; then
        return 0
    else
        return 1
    fi
}

function wait_dom_stop {
    domname=$1
    timeout=$2
    i=0
    while [ $i -lt $timeout ] ; do
        if ! dom_exists "$domname" ; then
            echo
            return 0
        fi
        sleep 1
        echo -n "."
    done
    echo
    return 1
}

function wait_ping {
    ping_host=$1
    timeout=$2
    i=0
    echo "Waiting for ${ping_host}..."
    while [ $i -lt $timeout ] ; do
        if ping -c 1 -w 1 $ping_host > /dev/null ; then
            echo
            return 0
        fi
        echo -n "."
    done
    echo
    return 1
}

function need_root {
    if [ "$USER" != "root" ] ; then
        echo "This script must be run as root!" >&2
        exit 1
    fi
}

