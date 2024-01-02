const std = @import("std");
const at = @import("ansi-term");
const clear = at.clear;
const cursor = at.cursor;
const git2 = @cImport(@cInclude("git2.h"));

fn discover_repository(path: []const u8) ?Repository {
    var buf = git2.git_buf{};
    _ = git2.git_libgit2_init();
    var repo: ?*git2.git_repository = null;
    const ret = git2.git_repository_discover(&buf, @ptrCast(path.ptr), 1, null);
    if (ret < 0) {
        return null;
    }
    _ = git2.git_repository_open(&repo, buf.ptr);
    return Repository.new(repo.?, &buf);
}

const Repository = struct {
    repo: *git2.git_repository,
    path: []const u8,
    gitBuffer: *git2.git_buf,

    fn new(repo: *git2.git_repository, buf: *git2.git_buf) Repository {
        return Repository{ .repo = repo, .path = std.mem.span(git2.git_repository_path(repo)), .gitBuffer = buf };
    }

    fn free(self: Repository) void {
        git2.git_repository_free(self.repo);
        _ = git2.git_libgit2_shutdown();
        git2.git_buf_dispose(self.gitBuffer);
    }

    fn path(self: Repository) []const u8 {
        return self.path;
    }

    // TODO: fix on new repositories
    fn has_staged_changes(self: Repository) bool {
        var git_status_options = git2.git_status_options{ .version = git2.GIT_STATUS_OPTIONS_VERSION };
        var status_list: ?*git2.git_status_list = null;
        git_status_options.show = git2.GIT_STATUS_SHOW_INDEX_ONLY;
        // zig fmt: off
        git_status_options.flags = git2.GIT_STATUS_OPT_INCLUDE_UNTRACKED 
            | git2.GIT_STATUS_OPT_RENAMES_HEAD_TO_INDEX 
            | git2.GIT_STATUS_OPT_INCLUDE_IGNORED;
        // zig fmt: on
        const err = git2.git_status_list_new(&status_list, self.repo, &git_status_options);
        if (err < 0) {
            std.debug.print("error: {d}\n", .{err});
            const gitError = git2.git_error_last();
            std.debug.print("error: {s}\n", .{std.mem.span(gitError.*.message)});
            return false;
        }
        defer git2.git_status_list_free(status_list);

        const max_i = git2.git_status_list_entrycount(status_list);
        for (0..max_i) |i| {
            const s = git2.git_status_byindex(status_list, i).*;
            // zig fmt: off
            if (checkStatus(s, git2.GIT_STATUS_INDEX_NEW) or 
                checkStatus(s, git2.GIT_STATUS_INDEX_MODIFIED) or 
                checkStatus(s, git2.GIT_STATUS_INDEX_DELETED) or 
                checkStatus(s, git2.GIT_STATUS_INDEX_RENAMED) or 
                checkStatus(s, git2.GIT_STATUS_INDEX_TYPECHANGE)) {
                // zig fmt: on
                return true;
            }
        }
        return false;
    }
};

fn checkStatus(status: git2.git_status_entry, checkVal: c_int) bool {
    std.debug.print("status: {d}\n", .{status.status});
    const stat: c_int = @bitCast(status.status);
    return stat & checkVal != 0;
}

fn check(status: git2.git_status_entry, checkVals: anytype) bool {
    for (checkVals) |checkVal| {
        if (checkStatus(status, checkVal)) {
            return true;
        }
    }
}

fn createTerminalList(writer: anytype, list: anytype, index: usize) !void {
    for (list, 0..) |item, idx| {
        if (index == idx) {
            try writer.print(">{s}\n", .{item});
        } else {
            try writer.print(" {s}\n", .{item});
        }
    }
}

pub fn main() !void {
    const writer = std.io.getStdOut().writer();
    clear.clearScreen(writer);

    // TODO: Add functionality to read from tty
    // const terminalList = [_][]const u8{ "a", "b", "c" };
    const repo = discover_repository(".");
    // var idx: usize = 0;

    while (repo) |repository| {
        defer repository.free();
        std.debug.print("{s}\n", .{repository.path});
        if (!repository.has_staged_changes()) {
            std.debug.print("no staged changes\n", .{});
        }
        break;
    } else {
        std.debug.print("error: could not open repository or not a repo\n", .{});
    }
}
