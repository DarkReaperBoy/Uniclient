//go:build !js

package cores

import (
	"fmt"
	"strings"

	"github.com/gotd/td/tg"
)

const streamPartLimit = 1 << 20

func (t *TelegramCore) FileLocationOf(fileRef FileRef) (tg.InputFileLocationClass, error) {
	fileID, err := tgUserID(fileRef.ID)
	if err != nil {
		return nil, err
	}
	if fileID == 0 {
		return nil, fmt.Errorf("%w: empty file ID", ErrInvalidInput)
	}
	accessHash := t.GetCachedFileHash(fileID)
	fileReference := t.getCachedFileRef(fileID)
	if accessHash == 0 && fileRef.Extra != "" {
		accessHash, fileReference = DecodeFileExtra(fileRef.Extra)
		if accessHash != 0 {
			t.cacheFileInfo(fileID, accessHash, fileReference)
		}
	}
	if strings.HasPrefix(fileRef.MimeType, "image/") && fileRef.MimeType != "image/gif" {
		return &tg.InputPhotoFileLocation{
			ID:            fileID,
			AccessHash:    accessHash,
			FileReference: fileReference,
			ThumbSize:     "y",
		}, nil
	}
	return &tg.InputDocumentFileLocation{
		ID:            fileID,
		AccessHash:    accessHash,
		FileReference: fileReference,
	}, nil
}

func (t *TelegramCore) ReadFilePart(fileRef FileRef, offset, limit int64) ([]byte, error) {
	if offset < 0 || limit <= 0 {
		return nil, fmt.Errorf("%w: bad range offset=%d limit=%d", ErrInvalidInput, offset, limit)
	}
	if offset%4096 != 0 {
		return nil, fmt.Errorf("%w: offset %d not 4096-aligned", ErrInvalidInput, offset)
	}
	if limit > streamPartLimit {
		limit = streamPartLimit
	}
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	loc, err := t.FileLocationOf(fileRef)
	if err != nil {
		return nil, err
	}
	res, err := api.UploadGetFile(ctx, &tg.UploadGetFileRequest{
		Location: loc,
		Offset:   offset,
		Limit:    int(limit),
		Precise:  true,
	})
	if err != nil {
		if strings.Contains(err.Error(), "FILE_MIGRATE") {
			return nil, fmt.Errorf("upload.getFile: FILE_MIGRATE surfaced despite gotd's automatic DC redirect (redirect failed): %w", err)
		}
		return nil, err
	}
	f, ok := res.(*tg.UploadFile)
	if !ok || f == nil {
		return nil, fmt.Errorf("upload.getFile: unexpected result %T", res)
	}
	return f.Bytes, nil
}
