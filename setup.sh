#!/bin/bash

# Обновляем и обновляем системные пакеты
sudo apt update && sudo apt upgrade -y

# Устанавливаем необходимые пакеты
sudo apt install -y unzip gcc make logrotate git jq lz4 sed wget curl build-essential coreutils systemd

# Устанавливаем Go
sudo rm -rf /usr/local/go
go_package_url="https://go.dev/dl/go1.21.5.linux-amd64.tar.gz"
go_package_file_name=${go_package_url##*\/}
wget -q $go_package_url
sudo tar -C /usr/local -xzf $go_package_file_name
echo "export PATH=\$PATH:/usr/local/go/bin" >> ~/.profile
echo "export PATH=\$PATH:\$(go env GOPATH)/bin" >> ~/.profile
source ~/.profile

# Клонируем репозиторий и собираем проект
git clone https://github.com/babylonchain/babylon.git
cd babylon
git checkout v0.8.3
make build
sudo cp ./build/babylond /usr/local/bin/
cd

# Запрашиваем MONIKER у пользователя
read -p "Введите имя вашего валидатора (MONIKER): " MONIKER

# Конфигурируем babylond
babylond config set client chain-id bbn-test-3
babylond config set client keyring-backend test
babylond init $MONIKER --chain-id bbn-test-3

curl -Ls https://snapshots.polkachu.com/testnet-genesis/babylon/genesis.json > $HOME/.babylond/config/genesis.json
curl -Ls https://snapshots.polkachu.com/testnet-addrbook/babylon/addrbook.json > $HOME/.babylond/config/addrbook.json

sed -i -e "s|^seeds *=.*|seeds = \"3f472746f46493309650e5a033076689996c8881@babylon-testnet.rpc.kjnodes.com:16459\"|" $HOME/.babylond/config/config.toml

sed -i -e "s|^minimum-gas-prices *=.*|minimum-gas-prices = \"0.00001ubbn\"|" $HOME/.babylond/config/app.toml

sed -i \
  -e 's|^pruning *=.*|pruning = "custom"|' \
  -e 's|^pruning-keep-recent *=.*|pruning-keep-recent = "100"|' \
  -e 's|^pruning-keep-every *=.*|pruning-keep-every = "0"|' \
  -e 's|^pruning-interval *=.*|pruning-interval = "19"|' \
  $HOME/.babylond/config/app.toml

# Настройка systemd для автозапуска babylond
sudo tee /etc/systemd/system/babylond.service > /dev/null << EOF
[Unit]
Description=Babylon Node
After=network-online.target

[Service]
User=$USER
ExecStart=$(which babylond) start
Restart=on-failure
RestartSec=10
LimitNOFILE=10000

[Install]
WantedBy=multi-user.target
EOF

# Сброс всех узлов tendermint и запуск babylond
babylond tendermint unsafe-reset-all --home $HOME/.babylond --keep-addr-book

sudo systemctl daemon-reload
sudo systemctl enable babylond
sudo systemctl start babylond

# Устанавливаем node_exporter
cd $HOME && \
wget https://github.com/prometheus/node_exporter/releases/download/v1.2.0/node_exporter-1.2.0.linux-amd64.tar.gz && \
tar xvf node_exporter-1.2.0.linux-amd64.tar.gz && \
rm node_exporter-1.2.0.linux-amd64.tar.gz && \
sudo mv node_exporter-1.2.0.linux-amd64 node_exporter && \
chmod +x $HOME/node_exporter/node_exporter && \
mv $HOME/node_exporter/node_exporter /usr/bin && \
rm -Rvf $HOME/node_exporter/

sudo tee /etc/systemd/system/exporterd.service > /dev/null <<EOF
[Unit]
Description=node_exporter
After=network-online.target
[Service]
User=$USER
ExecStart=/usr/bin/node_exporter
Restart=always
RestartSec=3
LimitNOFILE=65535
[Install]
WantedBy=multi-user.target
EOF

sudo systemctl enable exporterd 
sudo systemctl restart exporterd

# Устанавливаем Docker
sudo apt install docker.io 

# Устанавливаем Docker Compose
sudo curl -L "https://github.com/docker/compose/releases/download/1.29.2/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose

sudo chmod +x /usr/local/bin/docker-compose

# Устанавливаем дополнительные компоненты
curl -O https://gitlab.com/shardeum/validator/dashboard/-/raw/main/installer.sh && chmod +x installer.sh && ./installer.sh
