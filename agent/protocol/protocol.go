package protocol

const ROLE_AGENT uint32 = 0

type AgentLoginReq struct {
	NodeId string
	Token  string
}

const MSG_LIST_NODE_HASHES = 2000

type ListNodeHashesReq struct {
	NodeId string
}

type ListNodeHashesRes struct {
	Error  string
	Hashes []string
}

const MSG_LISTWATCH_HASHES = 3000

type ListWatchHashesReq struct {
}

type ListWatchHashesRes struct {
	Hashes []string
	Error  string
}

const MSG_GET_HASH = 1300

type GetHashReq struct {
	Hash string
}

type GetHashRes struct {
	Url   string
	Error string
}
