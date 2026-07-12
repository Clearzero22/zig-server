comptime {
    _ = @import("router.test.zig");
    _ = @import("context.test.zig");
    _ = @import("server.test.zig");
}

// 集成测试 (启动 HTTP 服务器 + 真实请求验证)
// TODO: 需要单独的 test runner 或 build step，避免阻塞和泄漏问题
// 计划: zig build integration-test 作为独立的 CI 步骤

