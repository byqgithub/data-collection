package rw

import (
	"bytes"
	"io"
)

type Message struct {
	Id   uint32
	Body []byte
}

func WriteBytes(w io.Writer, b []byte) error {
	buffer := bytes.NewBuffer(make([]byte, 0, len(b)+4))
	var err error
	if b == nil {
		if _, err = buffer.Write(Uint32ToBytes(0xFFFFFFFF)); err != nil {
			return err
		}
	} else {
		if _, err = buffer.Write(Uint32ToBytes(uint32(len(b)))); err != nil {
			return err
		}
		if len(b) > 0 {
			if _, err = buffer.Write(b); err != nil {
				return err
			}
		}
	}

	if _, err = w.Write(buffer.Bytes()); err != nil {
		return err
	}
	return nil
}

func ReadBytes(r io.Reader, pb *[]byte) error {
	var err error
	var length uint32

	if err = ReadUint32(r, &length); err != nil {
		return err
	}
	if length == 0xFFFFFFFF {
		*pb = nil
		return nil
	} else if length == 0 {
		*pb = []byte{}
		return nil
	} else {
		b := make([]byte, length)
		if _, err = io.ReadFull(r, b); err != nil {
			return err
		}
		*pb = b
		return nil
	}
}

func ReadBytesAlt(r io.Reader) ([]byte, error) {
	var err error
	var length uint32

	if err = ReadUint32(r, &length); err != nil {
		return nil, err
	}
	if length == 0xFFFFFFFF {
		return nil, nil
	} else if length == 0 {
		return []byte{}, nil
	} else {
		b := make([]byte, length)
		if _, err = io.ReadFull(r, b); err != nil {
			return nil, err
		}
		return b, nil
	}
}
