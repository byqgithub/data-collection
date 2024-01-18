package rw

import (
	"bytes"
	"io"
)

func WriteUint32AndObject(w io.Writer, v uint32, o interface{}) error {
	b := bytes.NewBuffer(make([]byte, 0, 256))
	if err := WriteUint32(b, v); err != nil {
		return err
	}
	if err := WriteJsonObject(b, o); err != nil {
		return err
	}
	if _, err := w.Write(b.Bytes()); err != nil {
		return err
	}
	return nil
}

func WriteUint32AndUint32(w io.Writer, v uint32, v2 uint32) error {
	b := bytes.NewBuffer(make([]byte, 0, 8))
	if err := WriteUint32(b, v); err != nil {
		return err
	}
	if err := WriteUint32(b, v2); err != nil {
		return err
	}
	if _, err := w.Write(b.Bytes()); err != nil {
		return err
	}
	return nil
}

func WriteUint32AndString(w io.Writer, v uint32, s string) error {
	b := bytes.NewBuffer(make([]byte, 0, 256))
	if err := WriteUint32(b, v); err != nil {
		return err
	}
	if err := WriteString(b, s); err != nil {
		return err
	}
	if _, err := w.Write(b.Bytes()); err != nil {
		return err
	}
	return nil
}

func WriteUint32AndBytes(w io.Writer, v uint32, b []byte) error {
	_b := bytes.NewBuffer(make([]byte, 0, 256))
	if err := WriteUint32(_b, v); err != nil {
		return err
	}
	if err := WriteBytes(_b, b); err != nil {
		return err
	}
	if _, err := w.Write(_b.Bytes()); err != nil {
		return err
	}
	return nil
}
