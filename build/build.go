package build

// inject by go build ldflags, refer: build.sh
var (
	Version              string
	DevType              string
	BackendAddr          string
	DataChannelAddr      string
	TestBackendAddr      string
	TestDataChannelAddr  string
)
