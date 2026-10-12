import Darwin

/// Descriptor-only ACL policy shared by private update storage and diagnostics storage.
package enum BelugaDescriptorACL {
    package static func rejectAllowACL(_ descriptor: Int32) throws {
        guard let acl = acl_get_fd_np(descriptor, ACL_TYPE_EXTENDED) else {
            // Darwin reports ENOENT when an existing descriptor has no extended ACL.
            // Only that result on a still-valid regular file/directory means absent;
            // unsupported ACL reads, permission errors, and invalid descriptors fail closed.
            let aclError = errno
            var value = stat()
            guard aclError == ENOENT, Darwin.fstat(descriptor, &value) == 0,
                  value.st_mode & S_IFMT == S_IFREG || value.st_mode & S_IFMT == S_IFDIR else {
                throw Failure.unsafeDescriptor
            }
            return
        }
        defer { acl_free(UnsafeMutableRawPointer(acl)) }
        guard acl_valid(acl) == 0 else { throw Failure.unsafeDescriptor }
        for index in 0...Int(ACL_MAX_ENTRIES) {
            var entry: acl_entry_t?
            if acl_get_entry(acl, Int32(index), &entry) != 0 {
                guard errno == EINVAL else { throw Failure.unsafeDescriptor }
                return
            }
            guard index < Int(ACL_MAX_ENTRIES), let entry else { throw Failure.unsafeDescriptor }
            var tag = ACL_UNDEFINED_TAG
            guard acl_get_tag_type(entry, &tag) == 0, tag == ACL_EXTENDED_DENY else {
                throw Failure.unsafeDescriptor
            }
        }
        throw Failure.unsafeDescriptor
    }

    private enum Failure: Error { case unsafeDescriptor }
}
