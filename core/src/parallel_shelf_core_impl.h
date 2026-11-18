#pragma once

#include "logos_module_context.h"
#include <cstdint>
#include <string>

class ParallelShelfCoreImpl : public LogosModuleContext {
public:
    std::string snapshot();
    std::string fileSize(const std::string& path);
    std::string readPiece(const std::string& path, int64_t offset, int64_t size);
    std::string writePiece(const std::string& path, int64_t offset, const std::string& piece);
    std::string mkdir(const std::string& path);
    std::string fetchDest(const std::string& id, const std::string& ext);
    std::string holdFile(const std::string& cid);
    std::string writeHold(const std::string& cid, const std::string& path);
    std::string readHold(const std::string& cid);
    std::string holdRead(const std::string& path, int64_t offset, int64_t size, const std::string& key);
    std::string keepHold(const std::string& key, const std::string& cid);
    std::string stageShare(const std::string& path);
    std::string rememberSource(const std::string& cid, const std::string& path);
    std::string readSource(const std::string& cid);
    std::string copyFile(const std::string& src, const std::string& dest);
    std::string renderPage(const std::string& cid, int64_t page, int64_t width,
                           const std::string& dest);

protected:
    void onContextReady() override;
};
