Puppet::Type.type(:mediawiki_extension).provide(:mediawiki_extension) do
  
  desc = "Manage Media Wiki Extensions via Git"

  commands :cd   => "cd"
  commands :git  => "git"
  commands :rm   => "rm"
  commands :curl => "curl"

#  confine :osfamily => :RedHat
#  defaultfor :operatingsystem => [:CentOS, :RedHat]

  def doc_root
    resource[:doc_root]
  end
  
  def name
    resource[:name]
  end
  
  def source
    resource[:source]
  end
  
  def source_version
    resource[:source_version]
  end
  
  def instance
    resource[:instance]
  end

  def exists?
    File.exists?("#{doc_root}/extensions/#{name}/#{name}.php")
  end


  def create
    # Clone
    git('clone', "#{source}", "#{doc_root}/#{instance}/extensions/#{name}")
    
    # Checkout
    git('checkout', "#{source_version})
    
    # Update / Init Submodules
    exec("cd #{doc_root}/#{instance}/extensions/#{name} && git submodule update --init")
  end

  def destroy
    rm('-rf', "#{doc_root}/extensions/#{name}")
  end
end
