custom_type_info :: (info: *Type_Info_Struct) -> *Type_Info_Struct {
    // If no modifiers are set, we can skip the cache and modification logic entirely
    if context.toml.type_info_modifiers[0] == null then return info;

    assert(context.toml.type_info_cache.allocator.proc == null || context.toml.type_info_cache.allocator.proc == context.allocator.proc);
    modified_info_entry, is_new := find_or_add(*context.toml.type_info_cache, info); if !is_new return modified_info_entry.*;
    modified_info_entry.* = New(Type_Info_Struct, false);
    modified_info := modified_info_entry.*;
    modified_info.* = info.*;

    for context.toml.type_info_modifiers if !it break; else {
        modified_info.* = it(modified_info);
    }
    return modified_info;
}

// Collect all variables members and flattens `using` members excluding unions and enums
flatten_using_type_info :: #bake_arguments flatten_using_type_info_t(flatten_named=true);
flatten_unnamed_using_type_info :: #bake_arguments flatten_using_type_info_t(flatten_named=false);
flatten_using_type_info_t :: (info:*Type_Info_Struct, $flatten_named:bool) ->  Type_Info_Struct {
    flat_info := info.*;
    flattened: [..]Type_Info_Struct_Member;
    array_reserve(*flattened, info.members.count);

    for member: info.members {
        if member.flags & .USING && (flatten_named || !member.name) {
            member_base := variant_base(member.type);
            if member_base.type == .STRUCT { // NOTE: Enums can be using too
                member_info: *Type_Info_Struct = xx member_base;
                if !(member_info.textual_flags & .UNION) {
                    for sub_member: custom_type_info(member_info).members { // To benefit from cache and avoid allocations, we recurse via top level
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
    flat_info.members = flattened;
    return flat_info;
}
