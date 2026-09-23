// Ranged file reads — the core half of parity row 281 (slice 228):
// upload.getFile by byte range, which is what lets the engine start
// playback before the file has fully arrived. The layer's own docs call
// Precise "useful, for example, to stream videos by keyframes".
package cores

import (
	"fmt"
	"strings"

	"github.com/gotd/td/tg"
)

// streamPartLimit caps one ranged read (upload.getFile's 1 MiB ceiling);
// the engine asks for 512 KiB chunks, this clamps anything bigger.
const streamPartLimit = 1 << 20

// fileLocationOf resolves a FileRef into the upload location (document
// or photo), consulting the in-memory caches first and the Extra field
// as fallback — the exact logic DownloadFile carried inline, extracted
// so the streaming path and full downloads cannot drift apart.
func (t *TelegramCore) fileLocationOf(fileRef FileRef) (tg.InputFileLocationClass, error) {
	fileID, err := tgUserID(fileRef.ID)
	if err != nil {
		return nil, err
	}
	if fileID == 0 {
		return nil, fmt.Errorf("%w: empty file ID", ErrInvalidInput)
	}
	// In-memory cache first, then Extra ("accessHash:base64ref").
	accessHash := t.getCachedFileHash(fileID)
	fileReference := t.getCachedFileRef(fileID)
	if accessHash == 0 && fileRef.Extra != "" {
		accessHash, fileReference = decodeFileExtra(fileRef.Extra)
		if accessHash != 0 {
			t.cacheFileInfo(fileID, accessHash, fileReference)
		}
	}
	// Photos use InputPhotoFileLocation (largest size "y"); everything
	// else — files, videos, audio, stickers — uses the document
	// location. image/gif is a document, not a photo.
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

// ReadFilePart returns up to limit bytes at offset — the chunked
// upload.getFile read behind engine streaming (row 281). offset must be
// 4096-aligned (the engine's chunk boundaries are; unaligned requests
// are a programming error and are rejected here rather than sent and
// failed at the layer), and Precise relaxes the remaining limit checks.
// DC migration needs no code here: gotd's invoker intercepts
// FILE_MIGRATE/STATS_MIGRATE and reruns the call on a sub-connection to
// the target DC (telegram client.go invokeDirect → invokeSub) — the
// exact chain DownloadFile (downloader → same api) and the thumb path
// already ride to cross DCs. If a FILE_MIGRATE error still reaches the
// caller, the redirect itself failed: it is wrapped with that context
// and the raw error preserved (BUGS.md B-2, premise corrected).
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
	// withAPI rule: never hold t.mu across the RPC.
	api, ctx, err := t.withAPI()
	if err != nil {
		return nil, err
	}
	loc, err := t.fileLocationOf(fileRef)
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
			// gotd consumes FILE_MIGRATE in invokeDirect (redirect to a
			// sub-connection on the target DC), so one that surfaces here
			// means the automatic redirect itself failed. Keep the raw
			// error — the engine classifies read failures as retryable —
			// and say what happened.
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
