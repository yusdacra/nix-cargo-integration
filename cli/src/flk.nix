{
  inputs = {
    source = {
      url = "source_url";
      flake = false;
    };
    nci.url = "path:nci_source";
  };

  outputs = { source, nci, ... }@inputs:
    nci.lib.makeOutputs {
      root = source;
      overrides = {
        packageMetadata = _: {
          build = true;
          app = true;
        };
      };
    };
}
