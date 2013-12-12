require 'fedux_org/stdlib/filesystem'
include FeduxOrg::Stdlib::Filesystem

def root_directory
  CommandExec.root_directory
end

def in_directory( directory, &block )
  Dir.chdir( directory ) do
    block.call( directory)
  end
end

