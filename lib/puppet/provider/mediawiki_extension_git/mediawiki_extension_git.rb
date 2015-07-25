Puppet::Type.type(:mediawiki_extension_git).provide(:mediawiki_extension_git) do
  
  desc = "Manage Media Wiki Extensions via Git"

  commands :git  => "git"
  commands :ln   => "ln"
  commands :rm   => "rm"

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
    git('clone', "#{source}", "#{doc_root}/#{instance}/extensions/#{name}-")
    
    Dir.chdir("#{doc_root}/#{instance}/extensions/#{name}-") do
      # Checkout
      git('checkout', "#{source_version}")
    
      # Update / Init Submodules
      git('submodule', 'update', '--init')
    end

    Dir.chdir("#{doc_root}/#{instance}/extensions") do    
      ln('-snf', "#{name}-", "#{name}")
    end
  end

  def destroy
    rm('-rf', "#{doc_root}/extensions/#{name}-")
    rm('-rf', "#{doc_root}/extensions/#{name}")
  end
end
