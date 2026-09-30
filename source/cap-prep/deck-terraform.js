/* Terraform track. See deck-kubernetes.js for the field contract. */

window.DECK = (window.DECK || []).concat([

  /* ---------- basic ---------- */

  {
    id: 'tf-iac', track: 'terraform', level: 'basic',
    q: 'What is infrastructure as code?',
    say: [
      'Describing servers, networks and services in files instead of clicking them into existence.',
      'The files go in version control, so infrastructure gets review, history and rollback like application code.',
      'Terraform is one tool for it. Bicep, ARM, CloudFormation and Pulumi are others.'
    ],
    why: 'The real gain is not speed, it is that the description becomes the truth. If somebody asks why a server has that configuration, there is a file and a commit that answers, instead of somebody trying to remember.',
    ours: 'Our Terraform VM was reviewable before it existed and reversible after, which is the whole argument in one sentence.',
    src: 'https://developer.hashicorp.com/terraform/intro'
  },
  {
    id: 'tf-what', track: 'terraform', level: 'basic',
    q: 'What does Terraform actually do?',
    say: [
      'You describe the infrastructure you want. Terraform works out the difference between that and what exists, then makes the change.',
      'It is declarative. Not create this then create that, but this is what should be true.',
      'A provider is the plugin that knows how to talk to a specific API, such as Azure.'
    ],
    why: 'Scripts automate too. The difference is that a script tells you what it will attempt and Terraform tells you what will change, because it reads the world first.',
    ours: 'We wrote an Azure Local VM as code, planned it, applied it, confirmed it was running as a clustered VM, then destroyed it and confirmed nothing was left.',
    src: 'https://developer.hashicorp.com/terraform/intro'
  },
  {
    id: 'tf-provider', track: 'terraform', level: 'basic',
    q: 'What is a provider?',
    say: [
      'A plugin that translates Terraform resources into API calls for one platform.',
      'azurerm for Azure, aws for AWS, kubernetes for a cluster, and many more.',
      'You declare which providers and versions you need, and terraform init downloads them.'
    ],
    why: 'Providers are why one language covers many systems. It also means Terraform can only do what the provider supports, so a brand new service often has no resource yet.',
    ours: 'We used the azurerm provider, and had to disable its automatic resource provider registration because it tried to register something unrelated to what we were doing.',
    src: 'https://developer.hashicorp.com/terraform/language/providers'
  },
  {
    id: 'tf-resource', track: 'terraform', level: 'basic',
    q: 'What is a resource block, and what is a data source?',
    say: [
      'A resource is something Terraform creates and owns.',
      'A data source is something it only reads, to use as input.',
      'Both are addressed as type dot name, which is how you reference one from another.'
    ],
    why: 'The distinction is ownership. Terraform will never destroy a data source, because it never created it. Reading an existing resource group as data is the safe way to build inside something you must not touch.',
    ours: 'After destroying our VM, the only thing left in state was a read only resource group data source, which is how we knew the cleanup was complete.',
    src: 'https://developer.hashicorp.com/terraform/language/data-sources'
  },
  {
    id: 'tf-workflow', track: 'terraform', level: 'basic',
    q: 'What is the normal Terraform workflow?',
    say: [
      'init downloads providers and sets up the backend.',
      'plan shows what would change.',
      'apply makes the change.',
      'destroy removes what Terraform owns.',
      'fmt and validate tidy and check the code before any of that.'
    ],
    why: 'init is per configuration and per backend, not once ever. Forgetting it after changing providers or backends is the single most common first error.',
    ours: 'We ran that full cycle against Azure Local, including the destroy, because proving the teardown was part of the point.',
    src: 'https://developer.hashicorp.com/terraform/cli/commands'
  },
  {
    id: 'tf-vars', track: 'terraform', level: 'basic',
    q: 'How do variables and outputs work?',
    say: [
      'Variables are inputs, with an optional type, default and description.',
      'Outputs are values the configuration publishes when it is done, such as an address or an id.',
      'Values come from tfvars files, command line flags, or environment variables.'
    ],
    why: 'Outputs are also the interface between modules. One module publishes an id, another consumes it, and that reference is what creates the dependency between them.',
    ours: 'The module wrapper we used takes the VM name, image and network as inputs rather than having them hard coded.',
    src: 'https://developer.hashicorp.com/terraform/language/values'
  },

  /* ---------- foundation ---------- */

  {
    id: 'tf-plan', track: 'terraform', level: 'foundation',
    q: 'What is the difference between plan and apply?',
    say: [
      'Plan reads current state, compares it to the configuration, and prints what it would add, change or destroy. It changes nothing.',
      'Apply does it.',
      'The plan is the review artifact. It is what you show someone before touching production.'
    ],
    why: 'Plan output is also the safety check. Three to add and zero to destroy is a very different conversation from three to add and one to destroy, and seeing destroy in a plan you expected to be additive is the moment to stop.',
    ours: 'Our plan read 3 to add, 0 to change, 0 to destroy. After destroy, a second plan read no objects need to be destroyed, which is how we proved the cleanup rather than assuming it.',
    src: 'https://developer.hashicorp.com/terraform/cli/commands/plan',
    diagram:
      '   config files          real world\n' +
      '   "what I want"         "what exists"\n' +
      '        \\                    /\n' +
      '         \\                  /\n' +
      '          v                v\n' +
      '        +--------------------+\n' +
      '        |   state file       |  "what I made, and where"\n' +
      '        +--------------------+\n' +
      '                 |\n' +
      '              PLAN = the difference\n' +
      '                 |\n' +
      '              APPLY = do it\n' +
      '\n' +
      '   remove the state file and it forgets it owns anything.'
  },
  {
    id: 'tf-state', track: 'terraform', level: 'foundation',
    q: 'What is Terraform state and why does everyone worry about it?',
    say: [
      'State maps the resources in your configuration to the real objects that exist.',
      'Without it Terraform cannot tell the difference between something it made and something it has never seen.',
      'It must be shared and locked for a team, and it can contain secrets, so it does not belong in Git.'
    ],
    why: 'State is an ownership record, not an inventory. It says these specific objects are mine. That is why importing something into state is serious: you are claiming the right to destroy it later.',
    ours: 'Ours is local, fine for a human operated proof and not fine for a pipeline. Our plan explicitly forbids importing the manual VMs, because that would put them under Terraform ownership.',
    src: 'https://developer.hashicorp.com/terraform/language/state'
  },
  {
    id: 'tf-idempotent', track: 'terraform', level: 'foundation',
    q: 'What does idempotent mean here, and why does it matter?',
    say: [
      'Running apply twice with no changes does nothing the second time.',
      'The result depends on the configuration, not on how many times you ran it.',
      'A correct run ends with a plan showing no changes.'
    ],
    why: 'It is what makes the code a description rather than a procedure. A shell script that creates a resource fails or duplicates on a second run. Because Terraform compares before acting, repeated runs are safe, which is what makes it usable in a pipeline.',
    ours: 'Our proof of completion was exactly this. After destroy, plan reported nothing left to do.',
    src: 'https://developer.hashicorp.com/terraform/language/resources/behavior'
  },

  /* ---------- working ---------- */

  {
    id: 'tf-drift', track: 'terraform', level: 'working',
    q: 'What happens if somebody changes something by hand?',
    say: [
      'That is drift. The real world no longer matches state.',
      'Terraform refreshes state at the start of a plan, so the next plan shows the difference.',
      'It will then offer to change it back, because the configuration is what you said you wanted.'
    ],
    why: 'This is the honest cost of infrastructure as code. It only works if it is the only way changes are made. A team that uses the portal for emergencies gets a tool that constantly proposes to undo their fixes.',
    ours: 'We hit a version of this. The VM extension stayed Accepted in Azure after the runtime had already succeeded, so local state had to be reconciled before we could continue.',
    src: 'https://developer.hashicorp.com/terraform/cli/commands/plan'
  },
  {
    id: 'tf-deps', track: 'terraform', level: 'working',
    q: 'How does Terraform know what order to build things in?',
    say: [
      'It builds a dependency graph from the references between resources.',
      'If a VM references a network interface id, Terraform knows the interface comes first. You do not order anything by hand.',
      'depends_on exists for real dependencies that no reference expresses.'
    ],
    why: 'Implicit dependency through reference is why the code reads as description rather than sequence. Reaching for depends_on often means the configuration is not expressing a relationship that actually exists.',
    ours: 'Our stack was an Arc machine, a network interface and a VM instance, and the order came from the references between them.',
    src: 'https://developer.hashicorp.com/terraform/language/resources/behavior',
    diagram:
      '  you write this, in any order:\n' +
      '\n' +
      '    resource "nic"     { ... }\n' +
      '    resource "vm"      { nic_id = nic.id }   <- a reference\n' +
      '    resource "machine" { ... }\n' +
      '\n' +
      '  terraform derives this:\n' +
      '\n' +
      '    machine ---> nic ---> vm\n' +
      '\n' +
      '  and destroys in reverse. no ordering written by hand.'
  },
  {
    id: 'tf-modules', track: 'terraform', level: 'working',
    q: 'What is a module, and what is an Azure Verified Module?',
    say: [
      'A module is a reusable group of resources with inputs and outputs. Every configuration is already a module, the root one.',
      'You use modules so the same pattern is not written five times slightly differently.',
      'Azure Verified Modules are Microsoft published modules that follow a common specification.'
    ],
    why: 'The tradeoff is real. A module hides detail, which is the point, and means you are trusting somebody else description of what good looks like. Fine when maintained, a problem when abandoned.',
    ours: 'We used an Azure Verified Module wrapper for the test VM rather than writing the resources by hand.',
    src: 'https://developer.hashicorp.com/terraform/language/modules'
  },
  {
    id: 'tf-count-foreach', track: 'terraform', level: 'working',
    q: 'How do you create several similar resources?',
    say: [
      'count gives you a numbered list. for_each gives you a keyed map or set.',
      'for_each is usually better, because resources are addressed by key rather than by index.',
      'With count, removing the middle item renumbers everything after it and Terraform plans to destroy and recreate them.'
    ],
    why: 'This is a genuine foot gun and a good thing to know unprompted. Index based addressing means a list change can cause destruction of resources you did not touch, and the plan will tell you if you read it.',
    ours: 'Not used. We built one VM. Worth knowing because it is the first thing you hit when the pattern becomes a fleet.',
    src: 'https://developer.hashicorp.com/terraform/language/meta-arguments/for_each'
  },
  {
    id: 'tf-import', track: 'terraform', level: 'working',
    q: 'What does terraform import do, and when should you be careful?',
    say: [
      'It brings an existing object into state so Terraform starts managing it.',
      'It does not write the configuration for you. You still have to describe the resource to match.',
      'After importing, run a plan and expect no changes. If the plan wants to change things, your configuration does not match reality yet.'
    ],
    why: 'Import is a transfer of ownership. Once something is in state, a future destroy will remove it. That is why importing production resources by accident is the classic disaster story.',
    ours: 'Our plan explicitly forbids importing the two manual POC VMs, precisely so nothing can later destroy them as part of a Terraform run.',
    src: 'https://developer.hashicorp.com/terraform/cli/import'
  },
  {
    id: 'tf-backend', track: 'terraform', level: 'working',
    q: 'What is a backend and why does a team need a remote one?',
    say: [
      'A backend is where state is stored. Local is a file on your machine, remote is somewhere shared.',
      'A remote backend gives you shared state, locking so two applies cannot run at once, and access control.',
      'Azure Blob Storage, S3 and Terraform Cloud are common choices.'
    ],
    why: 'Locking is the reason people usually reach for it, and access control is the reason that actually matters, because state can contain secrets in plain text.',
    ours: 'Local state, which is honest for a human operated proof. Remote state is on the follow on list along with the pipeline identity that would use it.',
    src: 'https://developer.hashicorp.com/terraform/language/backend'
  },
  {
    id: 'tf-lifecycle', track: 'terraform', level: 'working',
    q: 'What is the lifecycle block for?',
    say: [
      'prevent_destroy refuses to destroy a resource, which fails the plan rather than doing it.',
      'ignore_changes tells Terraform not to care about a field something else manages.',
      'create_before_destroy builds the replacement before removing the original.'
    ],
    why: 'create_before_destroy is the one worth understanding. By default a replacement destroys first, which means downtime. Reversing it needs the resource to tolerate two existing briefly, which naming often prevents.',
    ours: 'Not used. Worth knowing because prevent_destroy is one honest answer to how do you stop this deleting production.',
    src: 'https://developer.hashicorp.com/terraform/language/meta-arguments/lifecycle'
  },

  /* ---------- pressed ---------- */

  {
    id: 'tf-vs-arm', track: 'terraform', level: 'pressed',
    q: 'Why Terraform rather than Bicep or ARM templates?',
    say: [
      'Bicep and ARM are Azure only. Terraform is multi provider, so one tool and language covers Azure, Kubernetes, DNS and more.',
      'Terraform keeps its own state, ARM relies on Azure to know what exists.',
      'Terraform has an explicit plan step as a first class artifact.',
      'Honestly, for Azure only work Bicep is a perfectly good answer and the choice is often about what a team already knows.'
    ],
    why: 'Do not oversell it. The strongest real argument for Terraform is one workflow across providers. The strongest argument for Bicep is native Azure support with no state to manage.',
    ours: 'This repo has both. Bicep for the Azure Local deployment itself, Terraform for the VM lifecycle test.',
    src: 'https://developer.hashicorp.com/terraform/intro'
  },
  {
    id: 'tf-secrets', track: 'terraform', level: 'pressed',
    q: 'How do you handle secrets in Terraform?',
    say: [
      'Do not put them in the configuration and do not put state in Git.',
      'Mark variables sensitive so they are redacted from output, but know they are still in state in plain text.',
      'Better is not to have the secret: use a managed identity, or pull it from a vault at runtime.'
    ],
    why: 'sensitive is an output filter, not encryption. Anyone who can read state can read the value. That is the real reason remote state with access control matters, more than locking.',
    ours: 'Not solved here and named as follow on work, along with OIDC based identity instead of stored credentials.',
    src: 'https://developer.hashicorp.com/terraform/language/state/sensitive-data'
  },
  {
    id: 'tf-pipeline', track: 'terraform', level: 'pressed',
    q: 'What changes when Terraform moves from your laptop into a pipeline?',
    say: [
      'State has to be remote and locked, because the runner is not your machine.',
      'Identity has to be a workload identity rather than your credentials. OIDC federation rather than a stored secret.',
      'Plan and apply become separate stages, with the apply gated on a human approval and the plan carried across as an artifact.',
      'The blast radius has to be scoped, because the pipeline can now destroy things unattended.'
    ],
    why: 'The interesting risk is that the thing which was safe because a person was watching now runs on its own. Applying a plan that was reviewed, rather than replanning at apply time, is what keeps the review meaningful.',
    ours: 'Ours is deliberately human operated. Remote state, OIDC, and protected apply environments are all listed as follow on work rather than claimed.',
    src: 'capstone/terraform-cicd-plan.md'
  },
  {
    id: 'tf-limits', track: 'terraform', level: 'pressed',
    q: 'Where does Terraform struggle?',
    say: [
      'Anything the provider does not model. If the API has a feature and the provider has not exposed it, you are stuck.',
      'Long asynchronous operations, where the API reports success before the thing is actually usable.',
      'Configuration inside a machine. Terraform builds the VM, it is not a configuration management tool for what runs on it.',
      'State conflicts and drift in an estate where people also click.'
    ],
    why: 'Naming the async problem is a credibility marker, because everyone who has used it against a real cloud has been bitten by a resource reporting complete while still settling.',
    ours: 'We hit precisely that. The Azure Local VM extension stayed Accepted at the ARM layer after Hyper-V had already reported the VM running normally, and again after the delete.',
    src: 'docs/planning/kubernetes-terraform-integration-test-results.md'
  }
]);
