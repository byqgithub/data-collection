package rw

import (
	"encoding/binary"
	"io"
)

func Uint64ToBytes(i uint64) []byte {
	b := make([]byte, 4)
	binary.BigEndian.PutUint64(b, i)
	return b
}
func Uint32ToBytes(i uint32) []byte {
	b := make([]byte, 4)
	binary.BigEndian.PutUint32(b, i)
	return b
}
func Uint16ToBytes(i uint16) []byte {
	b := make([]byte, 2)
	binary.BigEndian.PutUint16(b, i)
	return b
}

func BytesToUint64(b []byte) uint64 {
	return binary.BigEndian.Uint64(b)
}

func BytesToUint32(b []byte) uint32 {
	return binary.BigEndian.Uint32(b)
}

func BytesToUint16(b []byte) uint16 {
	return binary.BigEndian.Uint16(b)
}

func WriteUint64(w io.Writer, v uint64) error {
	b := make([]byte, 8)
	binary.BigEndian.PutUint64(b, v)
	_, err := w.Write(b)
	return err
}

func ReadUint64(r io.Reader, v *uint64) error {
	b := make([]byte, 8)
	if _, err := io.ReadFull(r, b); err != nil {
		return err
	} else {
		*v = binary.BigEndian.Uint64(b)
		return err
	}
}

func ReadUint64Alt(r io.Reader) (uint64, error) {
	var v uint64
	if err := ReadUint64(r, &v); err != nil {
		return uint64(0), err
	} else {
		return v, nil
	}
}

func WriteUint32(w io.Writer, v uint32) error {
	b := make([]byte, 4)
	binary.BigEndian.PutUint32(b, v)
	_, err := w.Write(b)
	return err
}

func ReadUint32(r io.Reader, v *uint32) error {
	b := make([]byte, 4)
	if _, err := io.ReadFull(r, b); err != nil {
		return err
	} else {
		*v = binary.BigEndian.Uint32(b)
		return err
	}
	return nil
}

func ReadUint32Alt(r io.Reader) (uint32, error) {
	var v uint32
	if err := ReadUint32(r, &v); err != nil {
		return uint32(0), err
	} else {
		return v, nil
	}
}

func WriteUint16(w io.Writer, v uint16) error {
	b := make([]byte, 2)
	binary.BigEndian.PutUint16(b, v)
	_, err := w.Write(b)
	return err
}

func ReadUint16(r io.Reader, v *uint16) error {
	b := make([]byte, 2)
	if _, err := io.ReadFull(r, b); err != nil {
		return err
	} else {
		*v = binary.BigEndian.Uint16(b)
		return err
	}
}

func ReadUint16Alt(r io.Reader) (uint16, error) {
	var v uint16
	if err := ReadUint16(r, &v); err != nil {
		return uint16(0), err
	} else {
		return v, nil
	}
}
