package rw

import (
	"encoding/json"
	"io"
)

func ReadJsonObject(r io.Reader, o interface{}) error {
	if b, err := ReadBytesAlt(r); err != nil {
		return err
	} else if err = json.Unmarshal(b, o); err != nil {
		return err
	} else {
		return nil
	}
}

func WriteJsonObject(w io.Writer, o interface{}) error {
	b, err := json.Marshal(o)
	if err != nil {
		return err
	}
	return WriteBytes(w, b)
}
