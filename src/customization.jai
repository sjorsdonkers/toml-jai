custom_type_info_cached :: (info: *Type_Info_Struct) -> *Type_Info_Struct {
    assert(context.toml.type_info_cache.allocator.proc == null || context.toml.type_info_cache.allocator.proc == context.allocator.proc);

    modified_info_entry, is_new := find_or_add(*context.toml.type_info_cache, info); if !is_new return modified_info_entry.*;
    modified_info_entry.* = New(Type_Info_Struct, false);
    modified_info_entry.*.* = info.*;

    flatten_usings(modified_info_entry.*, flatten_named=true);

    return modified_info_entry.*;
}

// Collect all variables members and flattens `using` members excluding unions and enums
flatten_usings :: (info:*Type_Info_Struct, $flatten_named:bool) {
    flattened: [..]Type_Info_Struct_Member;
    array_reserve(*flattened, info.members.count);

    for member: info.members {
        if member.flags & .USING && (flatten_named || !member.name) {
            member_base := variant_base(member.type); // Should a variant be allowed to have it's own custom_type_info?
            if member_base.type == .STRUCT { // NOTE: Enums can be using too
                member_info: *Type_Info_Struct = xx member_base;
                if !(member_info.textual_flags & .UNION) {
                    for sub_member: custom_type_info_cached(member_info).members {
                        offset_sub_member := sub_member;
                        offset_sub_member.offset_in_bytes += member.offset_in_bytes;
                        array_add(*flattened, offset_sub_member);
                    }
                    continue;
                }
            }
        }
        array_add(*flattened, member);
    }
    info.members = flattened;
}
