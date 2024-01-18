package services

import (
	"net"
	"time"

	"github.com/PPIO/pi-collect/agent/protocol"
	"github.com/PPIO/pi-collect/pkg/rw"
	util "github.com/PPIO/pi-collect/pkg/util"

	log "github.com/sirupsen/logrus"
)

var (
	ListNodeHashesChan = make(chan struct{})
	LocalPluginChan    = make(chan []string, 1)
	receiveWatchChan   = make(chan bool, 1)
	pluginDownloadChan = make(chan bool, 1)
	PluginUpdateChan   = make(chan map[string]string, 1)
	PluginDeleteChan   = make(chan []string, 1)
	nodeHashes         []string
	receiveHashes      []string
	deletePlugins      []string
	addPlugins         []string
	lastHashes         []string
	HashMap            = make(map[string]string)
	ConfigServer       = "127.0.0.1:56780"
)

type Agent struct {
	Addr   string
	NodeId string
	Conn   net.Conn
}

func NewAgent(nodeId string, conn net.Conn) *Agent {
	return &Agent{
		NodeId: nodeId,
		Conn:   conn,
	}
}

func (a *Agent) ListNodeHashes() error {
	log.Debug("start list node hashes")
	var req protocol.AgentLoginReq
	req.Token = "admin"
	req.NodeId = a.NodeId
	err := rw.WriteUint32AndObject(a.Conn, protocol.ROLE_AGENT, req)
	if err != nil {
		log.Errorf("%+v", err)
		return err
	}

	var req2 protocol.ListNodeHashesReq
	req2.NodeId = a.NodeId
	err = rw.WriteUint32AndObject(a.Conn, protocol.MSG_LIST_NODE_HASHES, req2)
	if err != nil {
		return err
	}
	var res2 protocol.ListNodeHashesRes
	err = rw.ReadJsonObject(a.Conn, &res2)
	if err != nil {
		return err
	}
	if res2.Error != "" {
		log.Errorf("got error :%s\n", res2.Error)
	} else {
		if len(res2.Hashes) > 0 {
			nodeHashes = res2.Hashes
			for _, hash := range res2.Hashes {
				log.Debugf("list node hash %+v", hash)
			}
			ListNodeHashesChan <- struct{}{}
		}
	}
	return nil
}

func (a *Agent) ListWatchHashes() error {
	log.Debug("start list watch hashes")
	var req protocol.AgentLoginReq
	req.Token = "admin"
	req.NodeId = a.NodeId
	err := rw.WriteUint32AndObject(a.Conn, protocol.ROLE_AGENT, req)
	if err != nil {
		log.Errorf("%+v", err)
		return err
	}

	var req2 protocol.ListWatchHashesReq
	err = rw.WriteUint32AndObject(a.Conn, protocol.MSG_LISTWATCH_HASHES, req2)
	if err != nil {
		log.Errorf("%+v", err)
		return err
	}
	for {
		var res2 protocol.ListWatchHashesRes
		err = rw.ReadJsonObject(a.Conn, &res2)
		if err != nil {
			log.Errorf("%+v", err)
			return err
		}
		hashes := util.RemoveKeyFromSlice(res2.Hashes)
		log.Infof("hashes, %v", hashes)
		log.Infoln("len(hashes): ", len(hashes))
		if len(hashes) > 0 {
			receiveHashes = hashes
			for _, hash := range hashes {
				log.Infof("%+v", hash)
			}
			receiveWatchChan <- true
		}
	}
}

func (a *Agent) GetHash(hash string) (string, error) {
	var req protocol.AgentLoginReq
	req.NodeId = a.NodeId
	req.Token = "admin"
	err := rw.WriteUint32AndObject(a.Conn, protocol.ROLE_AGENT, req)
	if err != nil {
		log.Errorf("%+v", err)
		return "", err
	}
	log.Infof("get hash: %s", hash)
	var req2 protocol.GetHashReq
	req2.Hash = hash
	err = rw.WriteUint32AndObject(a.Conn, protocol.MSG_GET_HASH, req2)
	if err != nil {
		log.Errorf("+%v", err)
		return "", err
	}
	var res2 protocol.GetHashRes
	err = rw.ReadJsonObject(a.Conn, &res2)
	if err != nil {
		log.Errorf("+%v", err)
		return "", err
	}
	if res2.Error != "" {
		log.Errorf("got error :%s\n", res2.Error)
		return "", err
	}
	log.Infof("url: %s", res2.Url)
	return res2.Url, nil
}

func ParseWatchPlugin() {
	for {
		select {
		case <-receiveWatchChan:
			// TODO
			log.Infoln("ReceiveWatchChan")
			if len(lastHashes) > 0 {
				addPlugins, deletePlugins = util.DifferenceSlice(receiveHashes, lastHashes)
				if len(addPlugins) > 0 || len(deletePlugins) > 0 {
					lastHashes = receiveHashes
					pluginDownloadChan <- true
				}
			} else {
				if len(receiveHashes) > 0 {
					addPlugins = receiveHashes
					lastHashes = receiveHashes
					pluginDownloadChan <- true
				}
			}
		case <-ListNodeHashesChan:
			select {
			case localHashes, ok := <-LocalPluginChan:
				log.Debugf("localHashes: %v, nodeHashes: %v", localHashes, nodeHashes)
				if ok {
					if len(localHashes) > 0 && len(nodeHashes) > 0 {
						log.Debugf("DifferenceSlice")
						addPlugins, deletePlugins = util.DifferenceSlice(nodeHashes, localHashes)
						if len(addPlugins) > 0 || len(deletePlugins) > 0 {
							pluginDownloadChan <- true
						}
					} else {
						if len(nodeHashes) > 0 {
							addPlugins = nodeHashes
							pluginDownloadChan <- true
						}
					}

				}
			}
		case <-pluginDownloadChan:
			log.Infoln("PluginDownload")
			log.Infof("addPlugins : %v", addPlugins)
			GetUrl(addPlugins)
		}
	}
}

func AgentInit(nodeId string, serverAddr string) {
	ConfigServer = serverAddr
	go func() {
		for {
			conn, err := net.Dial("tcp", ConfigServer)
			if err != nil {
				log.Errorf("conn err: %v", err)
				time.Sleep(time.Second * 3)
			} else {
				err = NewAgent(nodeId, conn).ListWatchHashes()
				//conn.Close()
				if err != nil {
					conn.Close()
					continue
				}
				time.Sleep(time.Second * 3)
			}
		}
	}()

	go func() {
		StartListHashes(nodeId)
		//ticker := time.NewTicker(time.Minute * 60)
		//select {
		//case <-ticker.C:
		//	StartListHashes(nodeId)
		//}

	}()
}

func StartListHashes(nodeId string) {
	for i := 0; i < 3; i++ {
		conn, err := net.Dial("tcp", ConfigServer)

		if err != nil {
			log.Errorf("conn err: %v", err)
		} else {
			defer conn.Close()
			err = NewAgent(nodeId, conn).ListNodeHashes()
			if err != nil {
				log.Errorf("ListNodeHashes err: %v", err)
				continue
			}
			break
		}
	}

}
func GetUrl(hashes []string) {
	if len(hashes) > 0 {
		HashMap = make(map[string]string)

		for _, hash := range hashes {
			conn, err := net.Dial("tcp", ConfigServer)
			if err != nil {
				log.Errorf("%+v", err)

			}
			agent := NewAgent(util.DeviceId, conn)
			log.Infoln("hash: ", hash)
			url, err := agent.GetHash(hash)
			if err != nil {
				log.Errorf("get hash err: %v", err)
				_ = conn.Close()
				continue
			} else {
				log.Printf("hash: %s, url: %s", hash, url)
			}

			body, err := util.DownloadUrl(url)
			if err != nil {
				log.Errorf("DownloadUrl err: %v", err)
				continue
			} else {
				log.Printf("url: %s, body: %s", url, body)
				bodyMd5sum := util.GetMd5Hash(body)
				log.Printf("bodyMd5sum: %s", bodyMd5sum)
				if hash == bodyMd5sum {
					HashMap[hash] = body
				} else {
					log.Errorf("DownloadUrl: %s, check hash error", url)
				}
			}
			_ = conn.Close()
		}
	}
	log.Printf("HashMap: %v", HashMap)

	if HashMap != nil {
		PluginUpdateChan <- HashMap
	}
	if len(deletePlugins) > 0 {
		PluginDeleteChan <- deletePlugins
	}
}

//func readNewPlugin() {
//	path := "/ipaas/collect/test/"
//	files := util.FetchFiles(path)
//
//	pluginContent := make(map[string]string)
//	hashArray := make([]string, 0)
//	if len(files) > 0 {
//		for _, path := range files {
//			file, err := os.Open(path)
//			if err != nil {
//				log.Debugf("Read plugin file error: %v", err)
//				continue
//			}
//
//			content, err := ioutil.ReadAll(file)
//			hash := util.GetMd5Hash(string(content))
//			pluginContent[hash] = string(content)
//			hashArray = append(hashArray, hash)
//			func() { _ = file.Close() }()
//		}
//	}
//	//PluginUpdateChan <- pluginContent
//	PluginDeleteChan <- hashArray
//}
