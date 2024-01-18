package rw

import (
	"errors"
	"io"
)

func ReadError(r io.Reader, pe *error) error {
	var s string
	if err := ReadString(r, &s); err != nil {
		return err
	}
	return errors.New(s)
}

func ReadErrorAlt(r io.Reader) (error, error) {
	var s string
	if err := ReadString(r, &s); err != nil {
		return nil, err
	}
	return errors.New(s), nil
}

func WriteError(w io.Writer, e error) error {
	return WriteString(w, e.Error())
}
