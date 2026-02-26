sudo yum update -y
sudo yum install wget -y
sudo yum install java-17-amazon-corretto-jmods -y
sudo mkdir /app && cd /app
sudo wget https://download.sonatype.com/nexus/3/nexus-3.79.1-04-linux-x86_64.tar.gz
sudo tar -xvf nexus-3.79.1-04-linux-x86_64.tar.gz
sudo mv nexus-3.79.1-04 nexus
sudo adduser nexus
sudo chown -R nexus:nexus /app/nexus
sudo chown -R nexus:nexus /app/sonatype*
sudo sed -i '27  run_as_user="nexus"' /app/nexus/bin/nexus
sudo tee /etc/systemd/system/nexus.service > /dev/null << EOL
[Unit]
Description=nexus service
After=network.target

[Service]
Type=forking
LimitNOFILE=65536
User=nexus
Group=nexus
ExecStart=/app/nexus/bin/nexus start
ExecStop=/app/nexus/bin/nexus stop
User=nexus
Restart=on-abort

[Install]
WantedBy=multi-user.target
EOL
sudo chkconfig nexus on
sudo systemctl start nexus
sudo systemctl enable nexus
sudo systemctl status nexus

-----------------------------------

#!/bin/bash
set -Eeuo pipefail

echo "========== NEXUS INSTALL (t3.small SAFE) =========="

# Must be root
if [ "$EUID" -ne 0 ]; then
  echo "Run as root"
  exit 1
fi

#################################
# Step 1: Update system
#################################
yum update -y

#################################
# Step 2: Swap (2GB)
#################################
SWAPFILE=/swapfile
if ! swapon --show | grep -q "$SWAPFILE"; then
  fallocate -l 2G $SWAPFILE
  chmod 600 $SWAPFILE
  mkswap $SWAPFILE
  swapon $SWAPFILE
  echo "$SWAPFILE swap swap defaults 0 0" >> /etc/fstab
fi

#################################
# Step 3: Java
#################################
yum install -y java-11-amazon-corretto wget

#################################
# Step 4: nexus user
#################################
id nexus &>/dev/null || useradd nexus

#################################
# Step 5: Cleanup old installs
#################################
systemctl stop nexus 2>/dev/null || true
systemctl disable nexus 2>/dev/null || true
rm -rf /opt/nexus /opt/sonatype-work /etc/systemd/system/nexus.service
rm -rf /opt/nexus-3*
systemctl daemon-reload

#################################
# Step 6: Download Nexus (stable)
#################################
cd /opt
NEXUS_VERSION="3.68.1-02"
wget https://download.sonatype.com/nexus/3/nexus-${NEXUS_VERSION}-unix.tar.gz
tar -xzf nexus-${NEXUS_VERSION}-unix.tar.gz
mv nexus-${NEXUS_VERSION} nexus
rm -f nexus-${NEXUS_VERSION}-unix.tar.gz

#################################
# Step 7: Permissions
#################################
chown -R nexus:nexus /opt/nexus /opt/sonatype-work
chmod +x /opt/nexus/bin/nexus

#################################
# Step 8: JVM TUNING (THIS IS THE FIX)
#################################
cat > /opt/nexus/bin/nexus.vmoptions <<EOF
-Xms512m
-Xmx1024m
-XX:MaxDirectMemorySize=1024m
-XX:+UnlockDiagnosticVMOptions
-XX:+LogVMOutput
-XX:LogFile=../sonatype-work/nexus3/log/jvm.log
-XX:-OmitStackTraceInFastThrow
-Djava.net.preferIPv4Stack=true
-Dkaraf.home=.
-Dkaraf.base=.
-Dkaraf.data=../sonatype-work/nexus3
-Dkaraf.log=../sonatype-work/nexus3/log
-Djava.io.tmpdir=../sonatype-work/nexus3/tmp
EOF

chown nexus:nexus /opt/nexus/bin/nexus.vmoptions

#################################
# Step 9: Run as nexus user
#################################
sed -i 's/^#run_as_user=""/run_as_user="nexus"/' /opt/nexus/bin/nexus.rc

#################################
# Step 10: systemd service
#################################
cat > /etc/systemd/system/nexus.service <<EOF
[Unit]
Description=Nexus Repository Manager
After=network.target

[Service]
Type=forking
User=nexus
Group=nexus
LimitNOFILE=65536
ExecStart=/bin/bash /opt/nexus/bin/nexus start
ExecStop=/bin/bash /opt/nexus/bin/nexus stop
Restart=on-failure
TimeoutStartSec=300

[Install]
WantedBy=multi-user.target
EOF

#################################
# Step 11: Start Nexus
#################################
systemctl daemon-reload
systemctl enable nexus
systemctl restart nexus

#################################
# Step 12: FINAL VALIDATION
#################################
echo "Waiting for Nexus to start (this takes time)..."
sleep 90

if systemctl is-active --quiet nexus && ss -lnt | grep -q ':8081'; then
  echo "======================================"
  echo "✅ SUCCESS: NEXUS IS RUNNING"
  echo "🌐 URL: http://<EC2_PUBLIC_IP>:8081"
  echo "======================================"
else
  echo "❌ FAILURE: Nexus still not running"
  systemctl status nexus --no-pager
  exit 1
fi



give execute permission before running --> chmod +x nexus.sh
./nexus.sh

