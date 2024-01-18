package rw

import (
	"io"
)

func WriteString(w io.Writer, s string) error {
	return WriteBytes(w, []byte(s))
}

func ReadString(r io.Reader, ps *string) error {
	if b, err := ReadBytesAlt(r); err != nil {
		return err
	} else {
		*ps = string(b)
		return nil
	}
}

func ReadStringAlt(r io.Reader) (string, error) {
	if b, err := ReadBytesAlt(r); err != nil {
		return "", err
	} else {
		return string(b), nil
	}
}
