#toolchain_type(name = "toolchain_type")

terraform_sums_url_template = "https://releases.hashicorp.com/terraform/{0}/terraform_{0}_SHA256SUMS"
terraform_sums_sig_url_template = "https://releases.hashicorp.com/terraform/{0}/terraform_{0}_SHA256SUMS"
terraform_url_template = "https://releases.hashicorp.com/terraform/{0}/terraform_{0}_{1}_{2}.zip"

toolchains = {
    "terraform_linux": {
        "name": "terraform_linux",
        "exec_compatible_with": [ 
            "@bazel_tools//platforms:linux",
            "@bazel_tools//platforms:x86_64",
        ],
        "target_compatible_with": [ 
            "@bazel_tools//platforms:linux",
            "@bazel_tools//platforms:x86_64",
        ],
        "toolchain":":terraform_linux",
        "toolchain_type":"@io_bazel_rules_terraform//:toolchain_type",
        "host": "linux",
        "arch": "amd64",
        "url":"https://releases.hashicorp.com/terraform/0.13.7/terraform_0.13.7_linux_amd64.zip",
        "sha256":"4a52886e019b4fdad2439da5ff43388bbcc6cce9784fde32c53dcd0e28ca9957"
    },
    "terraform_osx": {
        "name": "terraform_osx",
        "exec_compatible_with": [
            "@bazel_tools//platforms:osx",
            "@bazel_tools//platforms:x86_64",
        ],
        "target_compatible_with": [
            "@bazel_tools//platforms:osx",
            "@bazel_tools//platforms:x86_64",
        ],
        "toolchain":":terraform_osx",
        "toolchain_type":"@io_bazel_rules_terraform//:toolchain_type",
        "host": "darwin",
        "arch": "amd64",
        "url":"https://releases.hashicorp.com/terraform/0.13.7/terraform_0.13.7_darwin_amd64.zip",
        "sha256":"d5fbb589bc35c2655d0705c26117135cbb25e4259f120415009e0e6427ea97c8"
    }
}

TerraformInfo = provider(
    doc = "Information on how to call terraform",
    fields = [
        "executable",
        "url",
        "sha256"
    ],
)

def _terraform_toolchain_impl(ctx):
    toolchain_info = platform_common.ToolchainInfo(
        terraforminfo = TerraformInfo(
            executable = ctx.attr.executable,
            url = ctx.attr.url,
            sha256 = ctx.attr.sha256
        ),
    )
    return [toolchain_info]

terraform_toolchain = rule(
    implementation = _terraform_toolchain_impl,
    attrs = {
        "executable": attr.string(),
        "url": attr.string(),
        "sha256": attr.string()
    }
)

def setup_terraform_toolchains():
    for name, toolchain in toolchains.items():
        terraform_toolchain(
            name = toolchain["name"],
            executable = "",
            url = toolchain["url"],
            sha256 = toolchain["sha256"])
        native.toolchain(
            name = "{0}_toolchain".format(toolchain["name"]),
            exec_compatible_with = toolchain["exec_compatible_with"],
            target_compatible_with = toolchain["target_compatible_with"],
            toolchain = toolchain["toolchain"],
            toolchain_type = toolchain["toolchain_type"]
        )

def _download_terraform_impl(ctx):
    if ctx.os.name == "linux":
        toolchain_name = "terraform_linux"
    elif ctx.os.name == "mac os x":
        toolchain_name = "terraform_osx"
    else:
        fail("Unsupported operating system: " + ctx.os.name)

    toolchain = toolchains[toolchain_name]

    # Download The SHA256SUM File
    # Download The SHA256SUM.sig File
    # Verify the SHA256SUM File Signature.
    # Extract the SHA256SUM for Terraform.
    # Download the Terraform Executable

    ctx.file("BUILD.bazel",
        """
filegroup(
    name = "terraform_executable",
    srcs = ["terraform/terraform"],
    visibility = ["//visibility:public"]
)
""",
        executable=False
    )
    ctx.download_and_extract(
        url = toolchain["url"],
        sha256 = toolchain["sha256"],
        output = "terraform",
        type = "zip",
    )

download_terraform = repository_rule(
    implementation = _download_terraform_impl,
    attrs = {
        "version": attr.string(
            mandatory = True
        )
    }
)

# TODO:  Need to define the plugin provider system
#def _terraform_provider_plugin_impl(ctx):
#    pass
#
#terraform_provider_plugin = repository_rule(
#    implementation = _terraform_provider_plugin_impl,
#    attrs = {
#        "name": attr.string(
#            mandatory = True
#        ),
#        "version": attr.string(
#            mandatory = True
#        )
#    }
#)

def _terraform_plan(ctx):
    deps = depset(ctx.files.srcs)
    ctx.actions.run(
        executable = ctx.executable._exec,
        inputs = deps.to_list(),
        outputs = [ctx.outputs.out],
        mnemonic = "TerraformInitialize",
        arguments = [
            "plan", 
            "-out={0}".format(ctx.outputs.out.path), deps.to_list()[0].dirname
        ]
    )

terraform_plan = rule(
    implementation = _terraform_plan,
    attrs = {
        "srcs": attr.label_list(
            mandatory = True,
            allow_files = True
        ),
        "_exec": attr.label(
            default = Label("@terraform_exec//:terraform_executable"),
            allow_files = True,
            executable = True,
            cfg = "host"
        )
    },
    toolchains = ["@io_bazel_rules_terraform//:toolchain_type"],
    outputs = {"out": "%{name}.out"},
)

def terraform_register_toolchains(version="0.13.7"):
    if "download_terraform" not in native.existing_rules():
        download_terraform(
            name = "terraform_exec",
            version = version
        )

    for name, toolchain in toolchains.items():
        native.register_toolchains(
            "//rules_terraform:{0}_toolchain".format(toolchain["name"]),
        )
