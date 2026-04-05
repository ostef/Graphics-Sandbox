BufferToUpload :: struct {
    src_buffer : GfxBuffer;
    dst_buffer : *GfxBuffer;
    size : int;
}

g_upload_buffers_to_destroy : [Gfx_Num_Frames_In_Flight][..]GfxBuffer;
g_buffer_uploads : [..]BufferToUpload;

QueueBufferUpload :: (buffer : *GfxBuffer, data : *void, size : int) {
    upload := ArrayPush(*g_buffer_uploads);
    upload.dst_buffer = buffer;
    upload.size = size;

    src_desc : GfxBufferDesc;
    src_desc.size = xx size;
    src_desc.usage = .TransferSrc;
    src_desc.memory_usage = .Upload;

    upload.src_buffer = CreateGfxBuffer("Upload Buffer", src_desc);
    ptr := GetMappedPtr(*upload.src_buffer);
    memcpy(ptr, data, size);
}

CleanupFinishedBufferUploads :: () {
    for g_upload_buffers_to_destroy[GetFrameInFlight()] {
        DestroyGfxBuffer(*it);
    }

    ArrayClear(*g_upload_buffers_to_destroy[GetFrameInFlight()]);
}

PerformPendingBufferUploads :: (pass : *GfxCopyPass) {
    CleanupFinishedBufferUploads();

    for * g_buffer_uploads {
        CopyBufferToBuffer(pass, *it.src_buffer, it.dst_buffer, 0, 0, xx it.size);
        ArrayPush(*g_upload_buffers_to_destroy[GetFrameInFlight()], it.src_buffer);
    }

    ArrayClear(*g_buffer_uploads);
}
