/* Docker track. See deck-kubernetes.js for the field contract. */

window.DECK = (window.DECK || []).concat([

  /* ---------- basic ---------- */

  {
    id: 'dk-what', track: 'docker', level: 'basic',
    q: 'What is Docker?',
    say: [
      'A way to package an application with everything it needs to run, and a runtime that runs those packages.',
      'The package is an image. A running copy is a container.',
      'The point is that it runs the same way on your laptop, a server, and in a cluster.'
    ],
    why: 'It solved a specific old problem, which is that software worked on one machine and not another because the machines differed. Packaging the dependencies with the application takes that difference away.',
    ours: 'We ran Docker inside a Linux VM on the cluster, which is the supported shape. You do not install it on the Azure Local hosts.',
    src: 'https://docs.docker.com/get-started/docker-overview/'
  },
  {
    id: 'dk-image-container', track: 'docker', level: 'basic',
    q: 'What is the difference between an image and a container?',
    say: [
      'An image is a read only template. A container is a running instance of one.',
      'Same relationship as a program on disk and a process.',
      'You can start many containers from one image, and each gets its own writable layer on top.'
    ],
    why: 'The writable layer is why a container is disposable. Anything written inside it dies with it unless it went to a volume. That is not a limitation, it is what makes containers interchangeable.',
    ours: 'We ran hello-world, which starts, prints and is removed, and Dockge, which is long running.',
    src: 'https://docs.docker.com/get-started/docker-concepts/the-basics/what-is-an-image/',
    diagram:
      '   image (read only, shared)\n' +
      '   +---------------------------+\n' +
      '   | layer 3  app files        |\n' +
      '   | layer 2  dependencies     |\n' +
      '   | layer 1  base os          |\n' +
      '   +---------------------------+\n' +
      '        ^              ^\n' +
      '        |              |\n' +
      '   +---------+    +---------+\n' +
      '   | write   |    | write   |   one thin writable layer each\n' +
      '   | layer   |    | layer   |   dies with the container\n' +
      '   +---------+    +---------+\n' +
      '   container A    container B'
  },
  {
    id: 'dk-not-vm', track: 'docker', level: 'basic',
    q: 'How is a container different from a virtual machine?',
    say: [
      'A VM virtualises hardware and runs its own kernel. A container is a process on the host kernel given a restricted view.',
      'That view comes from namespaces, which control what it can see, and cgroups, which control what it can use.',
      'So containers start in milliseconds and are much smaller, but they share the host kernel.'
    ],
    why: 'Sharing the kernel is the tradeoff and worth saying out loud. It is also why a Linux container cannot run on a Windows kernel without a Linux VM underneath it.',
    ours: 'This is exactly why our Docker work runs inside a VM on the cluster rather than on the Azure Local hosts.',
    src: 'https://docs.docker.com/get-started/docker-concepts/the-basics/what-is-a-container/',
    diagram:
      '   virtual machines            containers\n' +
      '   +------+ +------+           +----+ +----+ +----+\n' +
      '   | app  | | app  |           |app | |app | |app |\n' +
      '   | libs | | libs |           |libs| |libs| |libs|\n' +
      '   | OS   | | OS   |  <- each  +----+ +----+ +----+\n' +
      '   +------+ +------+     has   +------------------+\n' +
      '   +--------------+      a     |  one host kernel |\n' +
      '   |  hypervisor  |    kernel  +------------------+\n' +
      '   +--------------+            +------------------+\n' +
      '   |   hardware   |            |     hardware     |\n' +
      '   +--------------+            +------------------+'
  },
  {
    id: 'dk-dockerfile', track: 'docker', level: 'basic',
    q: 'What is a Dockerfile?',
    say: [
      'A text file of instructions for building an image.',
      'FROM picks the base image. RUN executes a build step. COPY brings files in. CMD sets what runs when a container starts.',
      'docker build turns it into an image, and you tag that image with a name.'
    ],
    why: 'It is a recipe, and it is also documentation. Anyone can read a Dockerfile and see exactly what is in the image, which is not true of a machine somebody configured by hand.',
    ours: 'Ours is nine lines. It starts from a Mariner core image on mcr rather than Docker Hub, installs ca-certificates and shadow-utils, creates an unprivileged appuser with a nologin shell, switches to it, and then echoes a line and sleeps.',
    src: 'https://docs.docker.com/reference/dockerfile/'
  },
  {
    id: 'dk-commands', track: 'docker', level: 'basic',
    q: 'What are the commands you actually use day to day?',
    say: [
      'docker run starts a container from an image. docker ps lists running ones, and ps -a includes stopped.',
      'docker logs shows what it printed. docker exec gets you a shell inside a running one.',
      'docker images lists what is on disk. docker stop and docker rm end and delete a container.',
      'docker pull and docker push move images to and from a registry.'
    ],
    why: 'exec and logs are the two you reach for when something is wrong. logs tells you what it said, exec lets you look around inside while it is still running.',
    ours: 'We used ps, images and logs to confirm the container came back after the VM was restarted.',
    src: 'https://docs.docker.com/reference/cli/docker/'
  },
  {
    id: 'dk-base-image', track: 'docker', level: 'basic',
    q: 'What is a base image and why does the choice matter?',
    say: [
      'The image your image starts from, named in FROM.',
      'It carries an operating system userland and whatever else it was built with.',
      'Everything in it is yours now: your attack surface, your patching obligation, your image size.'
    ],
    why: 'This is where most of the size and most of the vulnerabilities come from. A slim or distroless base can be tens of megabytes where a full distribution image is hundreds.',
    ours: 'Our smoke image uses a Microsoft base from mcr.microsoft.com rather than Docker Hub, which also avoids Docker Hub rate limits.',
    src: 'https://docs.docker.com/build/building/base-images/'
  },
  {
    id: 'dk-ports', track: 'docker', level: 'basic',
    q: 'How does traffic get into a container?',
    say: [
      'By default a container is on a private bridge network and is not reachable from outside the host.',
      'Publishing a port maps a host port to a container port, written as host colon container.',
      'Containers on the same user defined network can reach each other by container name.'
    ],
    why: 'The name resolution point is the useful one. On a user defined network Docker runs a small DNS, so a web container reaches a database container by name without knowing any address.',
    ours: 'Dockge publishes 5001, which is why it answers on the VM address from the DevBox and not just on localhost.',
    src: 'https://docs.docker.com/engine/network/'
  },

  /* ---------- foundation ---------- */

  {
    id: 'dk-layers', track: 'docker', level: 'foundation',
    q: 'What are image layers and why do they matter?',
    say: [
      'Each instruction in a Dockerfile produces a layer, and the image is those layers stacked.',
      'Layers are cached and shared. Two images on the same base share those layers on disk and over the network.',
      'A build reuses cached layers until the first instruction whose inputs changed, then rebuilds everything after it.'
    ],
    why: 'This drives how you order a Dockerfile. Copy your dependency manifest and install dependencies before you copy application source, because source changes every commit and dependencies do not. Backwards, and every build reinstalls everything.',
    ours: 'Our smoke Dockerfile installs packages, creates a user, drops privileges, and is deliberately minimal.',
    src: 'https://docs.docker.com/build/cache/',
    diagram:
      '  bad order                    good order\n' +
      '  COPY . .            <- any  COPY package.json .\n' +
      '  RUN install deps       code RUN install deps\n' +
      '                       change COPY . .\n' +
      '                       busts\n' +
      '                       cache\n' +
      '                       here\n' +
      '\n' +
      '  put the things that rarely change nearest the top.'
  },
  {
    id: 'dk-tags', track: 'docker', level: 'foundation',
    q: 'What is a registry, and what is wrong with the latest tag?',
    say: [
      'A registry stores and serves images. Docker Hub is one, Azure Container Registry and Microsoft Container Registry are others.',
      'A tag is a moving label. latest is just a tag with a conventional name and no special meaning.',
      'A digest is the immutable content hash. Pin by digest when you need the same bits.'
    ],
    why: 'latest makes a deployment irreproducible. Two machines pulling the same tag on different days can run different code, and nothing in the manifest records that it happened.',
    ours: 'Honest weakness on our side. The dashboard runs an image tagged latest. Fine for a proof, and exactly what you would not do in a pipeline.',
    src: 'https://docs.docker.com/get-started/docker-concepts/the-basics/what-is-a-registry/'
  },
  {
    id: 'dk-persist', track: 'docker', level: 'foundation',
    q: 'How does a container keep data?',
    say: [
      'It does not, by default. The writable layer dies with the container.',
      'A volume is storage managed by Docker and is the normal answer.',
      'A bind mount maps a host path into the container, useful in development and coupling you to the host layout.'
    ],
    why: 'This decides whether a workload is a good fit. Stateless services are easy. Anything that must not lose data needs a deliberate decision about where the data lives and what backs it up.',
    ours: 'Dockge keeps its stack definitions on a path in the VM. Nothing in our container work held data that mattered.',
    src: 'https://docs.docker.com/engine/storage/volumes/'
  },

  /* ---------- working ---------- */

  {
    id: 'dk-restart', track: 'docker', level: 'working',
    q: 'What brings a container back after a reboot?',
    say: [
      'A restart policy on the container, set at run time or in Compose.',
      'no is the default. always restarts it including after a daemon restart. unless-stopped is the same but respects a manual stop. on-failure only restarts on a non zero exit.',
      'The Docker daemon has to start at boot for any of it to work.'
    ],
    why: 'unless-stopped is usually what people actually want. always will restart something you deliberately stopped, the next time the host boots, which surprises people.',
    ours: 'We saw this directly. The Docker VM was powered off for days, and when it was started again the container came back on its own and answered on its port with no manual step.',
    src: 'https://docs.docker.com/engine/containers/start-containers-automatically/'
  },
  {
    id: 'dk-compose', track: 'docker', level: 'working',
    q: 'What is Docker Compose and where does it stop being enough?',
    say: [
      'Compose describes a set of containers, their networks and volumes, in one file, and brings them up together.',
      'It is scoped to a single host.',
      'No scheduling, no healing across machines, no rolling update. When you need those you are asking for an orchestrator.'
    ],
    why: 'This is the clean line between containers and Kubernetes. Compose is a very good answer for one machine, and the moment you care about that machine failing it stops being the answer.',
    ours: 'We ran Dockge, a web front end for Compose stacks, on a single VM. No orchestrator involved.',
    src: 'https://docs.docker.com/compose/'
  },
  {
    id: 'dk-entrypoint', track: 'docker', level: 'working',
    q: 'What is the difference between ENTRYPOINT and CMD?',
    say: [
      'ENTRYPOINT is the executable the container always runs. CMD is the default arguments.',
      'Anything you put after the image name on docker run replaces CMD, not ENTRYPOINT.',
      'With only CMD and no ENTRYPOINT, the whole command is replaceable.'
    ],
    why: 'The pattern is ENTRYPOINT for the tool and CMD for the default arguments, so the image behaves like a command line program. Getting it wrong makes an image that ignores the arguments you pass it.',
    ours: 'Our smoke image uses only CMD, which is right for something whose entire job is to print a line and wait.',
    src: 'https://docs.docker.com/reference/dockerfile/'
  },
  {
    id: 'dk-multistage', track: 'docker', level: 'working',
    q: 'What is a multi stage build for?',
    say: [
      'You build in one stage with the full toolchain, then copy only the finished artifact into a clean, smaller final stage.',
      'The compilers, source and build dependencies never reach the shipped image.',
      'It is smaller and it has less in it that can be exploited.'
    ],
    why: 'The security half matters as much as the size. A compiler and a package manager inside a running production container are useful to an attacker and useless to you.',
    ours: 'Not used. Our container work did not build application images, which is one of the honest gaps in the Docker evidence.',
    src: 'https://docs.docker.com/build/building/multi-stage/'
  },
  {
    id: 'dk-context', track: 'docker', level: 'working',
    q: 'What is the build context, and what does dockerignore do?',
    say: [
      'The build context is the directory you point docker build at. All of it gets sent to the builder before the build starts.',
      'dockerignore excludes paths from that, the same way gitignore does.',
      'Without it you can ship your git history, local secrets or node_modules into the build.'
    ],
    why: 'People notice this as a slow build and miss the real problem. If a secret file is in the context and a COPY picks it up, it is baked into a layer of the published image.',
    ours: 'Not an issue for us, because the smoke image copies nothing in.',
    src: 'https://docs.docker.com/build/concepts/context/'
  },
  {
    id: 'dk-logs', track: 'docker', level: 'working',
    q: 'Where should a container write its logs?',
    say: [
      'To standard out and standard error. The runtime collects them.',
      'Not to a file inside the container, because that file dies with the container and nobody can reach it.',
      'The platform then decides where they go, which is what makes central log collection possible.'
    ],
    why: 'This is one of the twelve factor conventions and it is why docker logs and kubectl logs work at all. An application that writes to its own log file is invisible to every tool built around containers.',
    ours: 'The dashboard prints request lines to stdout, which is how its access log is visible through kubectl logs.',
    src: 'https://docs.docker.com/engine/logging/'
  },

  /* ---------- deeper ---------- */

  {
    id: 'dk-security', track: 'docker', level: 'pressed',
    q: 'What are the obvious things to get right in an image?',
    say: [
      'Do not run as root. Create a user and drop to it.',
      'Start from a small maintained base, because everything in it is your attack surface and your patching obligation.',
      'Do not bake secrets into layers. A layer stays in the image even if a later instruction deletes the file.',
      'Pin what you depend on so a rebuild is reproducible.'
    ],
    why: 'The deleted secret point catches people. Removing a file in a later instruction does not remove it from the earlier layer, and anyone who pulls the image can read it back out.',
    ours: 'Our smoke image creates a user, drops privileges, and has no secrets. Its own labels say so.',
    src: 'https://docs.docker.com/build/building/best-practices/'
  },
  {
    id: 'dk-oci', track: 'docker', level: 'pressed',
    q: 'Is Docker the only way to run containers?',
    say: [
      'No. The image format and runtime behaviour are open standards under the OCI.',
      'containerd and CRI-O are runtimes. Podman and Buildah are alternative tools.',
      'Kubernetes does not use Docker as its runtime. It talks to a runtime through the CRI, usually containerd.'
    ],
    why: 'Worth knowing because the phrase Docker image is a habit rather than a fact. An image built by Docker runs under containerd in Kubernetes because both follow the same specification.',
    ours: 'Our AKS nodes run containerd. The image built by Docker conventions runs there unchanged.',
    src: 'https://opencontainers.org/'
  },
  {
    id: 'dk-namespaces', track: 'docker', level: 'pressed',
    q: 'What actually isolates a container, mechanically?',
    say: [
      'Linux namespaces give it a private view: its own process tree, network stack, mount table, hostname and users.',
      'cgroups limit what it can consume: CPU, memory, IO.',
      'Capabilities and seccomp reduce what it is allowed to ask the kernel to do.',
      'It is all one kernel underneath.'
    ],
    why: 'This is the honest answer to how strong is container isolation. It is a set of kernel features, not a hardware boundary, so a kernel vulnerability is a container escape in a way it is not for a VM.',
    ours: 'It is the reason the architecture puts Docker in a VM. The VM gives the hardware boundary, the container gives the packaging.',
    src: 'https://docs.docker.com/engine/security/'
  }
]);
