package = "laser"
version = "dev-1"
source = {
    url = "https://github.com/estoneman/laser.git",
    branch = "main"
}
description = {
    summary = "Personal DJ Workflow Automation",
    homepage = "https://github.com/estoneman/laser.git",
    license = "MIT"
}
dependencies = {
    "argparse >= 0.7",
    "inspect >= 3.1",
    "lua >= 5.1, < 5.5",
}
build = {
    type = "builtin",
    modules = {
        main = "src/main.lua"
    }
}
