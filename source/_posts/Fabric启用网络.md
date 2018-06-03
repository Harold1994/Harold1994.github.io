---
title: Fabric启用网络
date: 2018-05-02 20:19:01
tags: 区块链
---

> 本博客是作者在安装Fabric时所作记录，并不全面，详细的安装流程请到[Fabric官方教程](http://hyperledger-fabric.readthedocs.io/en/release-1.1/getting_started.html)一步一步进行

我们将使用cryptogen工具为我们的各种网络实体生成加密材料（x509证书和签名密钥）。 这些证书是身份的代表，它们允许在我们的实体进行通信和交易时进行签名/验证身份验证。

**手动生成证书和配置交易**
 <!-- more-->
- 生成证书和密钥：

```
../bin/cryptogen generate --config=./crypto-config.yaml
```

证书和密钥（即MSP材料）将被输出到第一个网络目录根目录下的一个目录 -  crypto-config中。

- 需要告诉configtxgen工具在哪里查找它需要获取的configtx.yaml文件。

  ```
  export FABRIC_CFG_PATH=$PWD 
  ```

- 调用configtxgen工具来创建ordererc初始块：

  ```
  ../bin/configtxgen -profile TwoOrgsOrdererGenesis -outputBlock ./channel-artifacts/genesis.block
  ```

**创建一个通道配置事务**

```
export CHANNEL_NAME=mychannel  && ../bin/configtxgen -profile TwoOrgsChannel -outputCreateChannelTx ./channel-artifacts/channel.tx -channelID $CHANNEL_NAME
```

- 接下来，我们将在我们正在构建的频道上为Org1定义锚点。

  ```
  ../bin/configtxgen -profile TwoOrgsChannel -outputAnchorPeersUpdate ./channel-artifacts/Org1MSPanchors.tx -channelID $CHANNEL_NAME -asOrg Org1MSP
  ```

- 为Org2定义锚点

```
../bin/configtxgen -profile TwoOrgsChannel -outputAnchorPeersUpdate ./channel-artifacts/Org2MSPanchors.tx -channelID $CHANNEL_NAME -asOrg Org2MSP
```

**启动网络**

```
docker-compose -f docker-compose-cli.yaml up -d
```

**环境变量**

```
docker exec -it cli bash
```

- 之前，我们使用configtxgen工具生成了配置交易channel.tx。我们将会传递这个交易到orderer作为创建channel请求的一部分

```
export CHANNEL_NAME=mychannel
```

```
peer channel create -o orderer.example.com:7050 -c $CHANNEL_NAME -f ./channel-artifacts/channel.tx --tls --cafile /opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/ordererOrganizations/example.com/orderers/orderer.example.com/msp/tlscacerts/tlsca.example.com-cert.pem
```

```
加入peer0.org1.example.com到通道。
 peer channel join -b mychannel.block
```

- 我们只需加入peer0.org2.example.com，以便我们可以正确更新我们通道中的锚点定义，而不是加入每个点。

```
CORE_PEER_MSPCONFIGPATH=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/org2.example.com/users/Admin@org2.example.com/msp CORE_PEER_ADDRESS=peer0.org2.example.com:7051 CORE_PEER_LOCALMSPID="Org2MSP" CORE_PEER_TLS_ROOTCERT_FILE=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/org2.example.com/peers/peer0.org2.example.com/tls/ca.crt peer channel join -b mychannel.block
```

- 应用程序通过链接代码与区块链分类帐进行交互。 因此，我们需要在每个将执行并支持我们的交易的对等方上安装链代码，然后在通道上实例化链代码。

```
peer chaincode install -n mycc -v 1.0 -p github.com/chaincode/chaincode_example02/go/
```

- 接下来，实例化通道上的链式代码。 这将初始化通道上的链代码，设置链代码的认可政策，并为目标对等体启动链代码容器。 记下-P参数。 这是我们的政策，我们指定所需的交易背书水平，以验证此链代码。

```
peer chaincode instantiate -o orderer.example.com:7050 --tls --cafile /opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/ordererOrganizations/example.com/orderers/orderer.example.com/msp/tlscacerts/tlsca.example.com-cert.pem -C $CHANNEL_NAME -n mycc -l node -v 1.0 -c '{"Args":["init","a", "100", "b","200"]}' -P "OR ('Org1MSP.peer','Org2MSP.peer')"
```

- 让我们查询a的值以确保链代码已正确实例化并且状态DB已填充。 查询的语法如下所示：

```
peer chaincode query -C $CHANNEL_NAME -n mycc -c '{"Args":["query","a"]}'
```

- 现在让我们将10从a移动到b。 该事务将切断一个新块并更新状态DB。 invoke的语法如下所示：

```
peer chaincode invoke -o orderer.example.com:7050  --tls --cafile /opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/ordererOrganizations/example.com/orderers/orderer.example.com/msp/tlscacerts/tlsca.example.com-cert.pem  -C $CHANNEL_NAME -n mycc -c '{"Args":["invoke","a","b","10"]}'
```

- 再查询

  ```peer chaincode query -c $channel_name -n mycc -c '{"args":["query","a"]}'
  peer chaincode query -C $CHANNEL_NAME -n mycc -c '{"Args":["query","a"]}'
  ```
