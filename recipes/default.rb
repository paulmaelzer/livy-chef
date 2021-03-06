my_ip = my_private_ip()
nn_endpoint = private_recipe_ip("apache_hadoop", "nn") + ":#{node.apache_hadoop.nn.port}"
home = node.apache_hadoop.hdfs.user_home


livy_dir="#{home}/#{node.livy.user}/livy"
apache_hadoop_hdfs_directory "#{livy_dir}" do
  action :create_as_superuser
  owner node.livy.user
  group node.apache_hadoop.group
  mode "1770"
  not_if ". #{node.apache_hadoop.home}/sbin/set-env.sh && #{node.apache_hadoop.home}/bin/hdfs dfs -test -d #{livy_dir}"
end

tmp_dirs   = [ livy_dir, "#{livy_dir}/rsc-jars", "#{livy_dir}/rpl-jars" ] 
for d in tmp_dirs
 apache_hadoop_hdfs_directory d do
    action :create
    owner node.livy.user
    group node.apache_hadoop.group
    mode "1777"
    not_if ". #{node.apache_hadoop.home}/sbin/set-env.sh && #{node.apache_hadoop.home}/bin/hdfs dfs -test -d #{d}"
  end
end

file "#{node.livy.home}/conf/livy.conf" do
 action :delete
end

template "#{node.livy.home}/conf/livy.conf" do
  source "livy.conf.erb"
  owner node.livy.user
  group node.livy.group
  mode 0655
  variables({ 
        :private_ip => my_ip,
        :nn_endpoint => nn_endpoint
           })
end


file "#{node.livy.home}/conf/spark-blacklist.conf" do
 action :delete
end

template "#{node.livy.home}/conf/spark-blacklist.conf" do
  source "spark-blacklist.conf.erb"
  owner node.livy.user
  group node.livy.group
  mode 0655
end

file "#{node.livy.home}/conf/livy-env.sh.erb" do
 action :delete
end

template "#{node.livy.home}/conf/livy-env.sh" do
  source "livy-env.sh.erb"
  owner node.livy.user
  group node.livy.group
  mode 0655
end

template "#{node.livy.home}/bin/start-livy.sh" do
  source "start-livy.sh.erb"
  owner node.livy.user
  group node.livy.group
  mode 0751
end

template "#{node.livy.home}/bin/stop-livy.sh" do
  source "stop-livy.sh.erb"
  owner node.livy.user
  group node.livy.group
  mode 0751
end



case node.platform
when "ubuntu"
 if node.platform_version.to_f <= 14.04
   node.override.livy.systemd = "false"
 end
end


service_name="livy"

if node.livy.systemd == "true"

  service service_name do
    provider Chef::Provider::Service::Systemd
    supports :restart => true, :stop => true, :start => true, :status => true
    action :nothing
  end

  case node.platform_family
  when "rhel"
    systemd_script = "/usr/lib/systemd/system/#{service_name}.service" 
  else
    systemd_script = "/lib/systemd/system/#{service_name}.service"
  end

  template systemd_script do
    source "#{service_name}.service.erb"
    owner "root"
    group "root"
    mode 0754
    notifies :enable, resources(:service => service_name)
    notifies :start, resources(:service => service_name), :immediately
  end

  hadoop_spark_start "reload_#{service_name}" do
    action :systemd_reload
  end  

else #sysv

  service service_name do
    provider Chef::Provider::Service::Init::Debian
    supports :restart => true, :stop => true, :start => true, :status => true
    action :nothing
  end

  template "/etc/init.d/#{service_name}" do
    source "#{service_name}.erb"
    owner node.livy.user
    group node.livy.group
    mode 0754
    notifies :enable, resources(:service => service_name)
    notifies :restart, resources(:service => service_name), :immediately
  end

end


if node.kagent.enabled == "true" 
   kagent_config service_name do
     service "YARN"
     start_script "service #{service_name} start"
     stop_script "service #{service_name} stop"
     log_file "#{node.livy.home}/livy.log"
     pid_file "#{node.livy.home}/livy.pid"
     web_port "#{node.livy.port}"
   end
end

