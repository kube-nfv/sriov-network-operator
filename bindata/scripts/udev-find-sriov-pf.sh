#!/bin/bash

UDEV_DIR="/host${SRIOV_HOST_UDEV_PATH:-/etc/udev}"
mkdir -p "${UDEV_DIR}"

cat <<'EOF' > "${UDEV_DIR}/disable-nm-sriov.sh"
#!/bin/bash
if [ ! -d "/sys/class/net/$1/device/physfn" ]; then
    exit 0
fi

pf_path=$(readlink /sys/class/net/$1/device/physfn -n)
pf_pci_address=${pf_path##*../}

if [ "$2" == "$pf_pci_address" ]; then
    echo "NM_UNMANAGED=1"
fi
EOF

chmod +x "${UDEV_DIR}/disable-nm-sriov.sh"
