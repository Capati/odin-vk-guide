---
sidebar_position: 1
description: External libraries and compilation guide.
---

# Project Setup

As in the original tutorial, we will use a companion Git project. This project serves as a
reference to help you if you get stuck.

## Prerequisites

- [Vulkan SDK](https://vulkan.lunarg.com/sdk/home) - provides essential components for Vulkan
  development
  - The SDK is installed globally, making it accessible across different development
    environments.
  - Check the installation by running the `vkcube` application.
- [Premake5](https://premake.github.io) - the build configuration to help compile external
  libraries
  - You can download the [Pre-Built Binaries](https://premake.github.io/download), simply
    need to be unpacked and placed somewhere on the system search path or any other
    convenient location.
  - For Unix, also requires **GNU libc 2.38**.
- [Git](http://git-scm.com/downloads) - required for the companion Git project and to clone
library dependencies
- C++ compiler - `vs2022` on Windows or `g++/clang` on Unix

## Prepare the Project

Make sure you have installed all the **prerequisites** listed above before continue.

1. Clone the [odin-vk-guide](https://github.com/Capati/odin-vk-guide.git) git repository with
   `--recursive` option to fetch the external libraries in submodules:

    ```bash
    git clone --recursive https://github.com/Capati/odin-vk-guide.git
    ```

    :::tip[Chapter code]

    The original tutorial has a Git repository to follow as a reference, with each chapter and
    section separated by branches. But to simplify, our repo has all chapter code inside the
    `tutorial` folder, where each chapter is a package.

    :::

    Now you can use the `src` folder to start coding. Of course, you can create your own
    project structure outside of this repo, just ensure you have the required files and
    external libraries in place or as as `collection` somewhere.

2. For the external libraries, you need to compile the follow:

    - **dear ImGui** located in `libs/imgui`
      - Repository: [odin-imgui](https://github.com/Capati/odin-imgui)
      - You only need the `glfw` and `vulkan` backends
    - **Vulkan Memory Allocator** located in `libs/vma`
      - Repository: [odin-vma](https://github.com/Capati/odin-vma)
      - Set the `--vk-version=3` to target Vulkan 1.3

    Follow the build instructions provided in each library's repository to successfully compile
    them before proceeding. Other libraries are either in `vendor` or does not require
    compilation.

## Building Project

To test that everything is prepared, lets go ahead and build the tutorial **2. Drawing with
Compute**, that section uses both ImGui and VMA.

```bash
odin run ./tutorial/02_drawing_with_compute -debug --out:./build/02_drawing_with_compute.exe --collection:libs=./libs
```

- `odin run` - This is the base command that tells the Odin compiler to compile and immediately
  execute the program.

- `./tutorial/02_drawing_with_compute` - This specifies the path to the Odin source code
directory that contains the program to be compiled and run. It's looking for the main package
in the `02_drawing_with_compute` directory inside the `tutorial` folder.

- `--debug` - This option compiles the program with debug information.

- `--out:./build/02_drawing_with_compute.exe` - This option defines where the compiled
executable should be saved. In this case, it will create `02_drawing_with_compute.exe` in the
`./build` directory. On Windows, you need to specify the executable name including the `.exe`
extension, on Unix, you can omit the extension.

- `--collection:libs=./libs` - This option adds a collection path. Collections in Odin are a way
to organize packages. This tells the compiler to look for additional packages in the `./libs`
directory, this is where the external libraries is located.

  :::danger[Collections]

  The tutorial uses the `libs` folder as a collection. Failing to do so will result in an error
  stating `Unknown library collection: 'libs'`. Ensure that the `libs` folder is correctly
  specified as a collection to avoid this issue.

  :::

### Script

Using the command line is fine, but we can use the provided scripts to automate the above
command.

```bash title="build.bat on Windows"
build.bat tutorial\02_drawing_with_compute
```

```bash title="build.sh on Unix"
# Before running this script for the first time, you'll need to make it executable:
# chmod +x ./build.sh
./build.sh tutorial/02_drawing_with_compute
```

The first argument is the package directory to build. Additionally, there is some optional
arguments: use `run` to immediately execute the program after compilation (equivalent to `odin
run`), or specify `release` to generate an optimized build.

### Visual Studio Code Tasks

If you are using **vscode** and prefer some UI to help build the tutorial, there is the option
to use the tasks system.

```json title=".vscode/tasks.json"
{
    "version": "2.0.0",
    "tasks": [
        {
            "label": "Run",
            "type": "shell",
            "windows": {
                "command": "build.bat tutorial/${input:tutorialName} run"
            },
            "linux": {
                "command": "./build.sh tutorial/${input:tutorialName} run"
            },
            "osx": {
                "command": "./build.sh tutorial/${input:tutorialName} run"
            },
            "group": {
                "kind": "build",
                "isDefault": true
            },
            "presentation": {
                "reveal": "always",
                "panel": "shared"
            },
            "problemMatcher": []
        },
    ],
    "inputs": [
        {
            "id": "tutorialName",
            "type": "pickString",
            "description": "Select the tutorial to run",
            "options": [
                "01_initializing_vulkan",
                "02_drawing_with_compute",
                "03_graphics_pipelines",
                "04_textures_and_engine_architecture",
                "05_gltf_loading",
            ]
        }
    ]
}
```

Note that we are still using the scripts to help build the examples. Learn more about tasks
from the official tutorial [Integrate with External Tools via Tasks][].

[Integrate with External Tools via Tasks]: https://code.visualstudio.com/Docs/editor/tasks
