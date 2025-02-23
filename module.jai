#module_parameters (
    CUSTOM_TYPE_TO_VALUE := #code custom_type_to_value(data, info)
);

using Data :: #import,file "src/data.jai";
#load "src/serialize.jai";
#load "src/deserialize.jai";
