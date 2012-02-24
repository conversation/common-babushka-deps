dep 'ready for update.repo', :git_ref_data, :env do
  env.default!(ENV['RAILS_ENV'] || ENV['RACK_ENV'] || 'production')
  requires [
    'valid git_ref_data.repo'.with(git_ref_data),
    'clean.repo',
    'before deploy'.with(ref_info[:old_id], ref_info[:new_id], ref_info[:branch], env)
  ]
end

dep 'up to date.repo', :git_ref_data, :env do
  env.default!(ENV['RAILS_ENV'] || ENV['RACK_ENV'] || 'production')
  requires [
    'on correct branch.repo'.with(ref_info[:branch]),
    'HEAD up to date.repo'.with(ref_info),
    'app bundled'.with(:root => '.', :env => env),

    # This and 'after deploy' below are separated so the deps in 'current dir'
    # they refer to load from the new code checked out by 'HEAD up to date.repo'.
    # Normally it would be fine because dep loading is lazy, but the "if Dep('...')"
    # checks trigger a source load when called.
    'on deploy'.with(ref_info[:old_id], ref_info[:new_id], ref_info[:branch], env),

    'app flagged for restart.task',
    'maintenance page down',
    'after deploy'.with(ref_info[:old_id], ref_info[:new_id], ref_info[:branch], env)
  ]
end

dep 'before deploy', :old_id, :new_id, :branch, :env do
  requires 'current dir:before deploy'.with(old_id, new_id, branch, env) if Dep('current dir:before deploy')
end
dep 'on deploy', :old_id, :new_id, :branch, :env do
  requires 'current dir:on deploy'.with(old_id, new_id, branch, env) if Dep('current dir:on deploy')
end
dep 'after deploy', :old_id, :new_id, :branch, :env do
  requires 'current dir:after deploy'.with(old_id, new_id, branch, env) if Dep('current dir:after deploy')
end

dep 'valid git_ref_data.repo', :git_ref_data do
  met? {
    git_ref_data[ref_data_regexp] || unmeetable!("Invalid git_ref_data '#{git_ref_data}'.")
  }
end

dep 'clean.repo' do
  setup {
    # Clear git's internal cache, which sometimes says the repo is dirty when it isn't.
    repo.repo_shell "git diff"
  }
  met? { repo.clean? || unmeetable!("The remote repo has local changes.") }
end

dep 'branch exists.repo', :branch do
  met? {
    repo.branches.include? branch
  }
  meet {
    log_block "Creating #{branch}" do
      repo.branch! branch
    end
  }
end

dep 'on correct branch.repo', :branch do
  requires 'branch exists.repo'.with(branch)
  met? {
    repo.current_branch == branch
  }
  meet {
    log_block "Checking out #{branch}" do
      repo.checkout! branch
    end
  }
end

dep 'HEAD up to date.repo', :old_id, :new_id, :branch do
  met? {
    (repo.current_full_head == new_id && repo.clean?).tap {|result|
      if result
        log_ok "#{branch} is up to date at #{repo.current_head}."
      else
        log "#{branch} needs updating: #{old_id[0...7]}..#{new_id[0...7]}"
      end
    }
  }
  meet {
    if old_id[/^0+$/]
      log "Starting HEAD at #{new_id[0...7]} (a #{shell("git rev-list #{new_id} | wc -l").strip}-commit history) since the repo is blank."
    else
      log shell("git diff --stat #{old_id}..#{new_id}")
    end
    repo.reset_hard! new_id
  }
end

dep 'app flagged for restart.task' do
  run {
    if File.exists? 'tmp/pids/unicorn.pid'
      shell "kill -USR2 #{'tmp/pids/unicorn.pid'.p.read}"
    else
      shell "mkdir -p tmp && touch tmp/restart.txt"
    end
  }
end

dep 'maintenance page up' do
  met? {
    !'public/system/maintenance.html.off'.p.exists? or
    'public/system/maintenance.html'.p.exists?
  }
  meet { 'public/system/maintenance.html.off'.p.copy 'public/system/maintenance.html' }
end

dep 'maintenance page down' do
  met? { !'public/system/maintenance.html'.p.exists? }
  meet { 'public/system/maintenance.html'.p.rm }
end

dep 'deployed migrations run', :old_id, :new_id, :env, :orm do
  setup {
    # If the branch was changed, git supplies 0000000 for old_id,
    # so the commit range is 'everything'.
    effective_old_id = old_id[/^0+$/] ? '' : old_id
    pending = shell("git diff --numstat #{effective_old_id}..#{new_id}").split("\n").grep(/^[\d\s]+db\/migrate\//)
    if pending.empty?
      log "No new migrations."
    else
      log "#{pending.length} migration#{'s' unless pending.length == 1} to run:"
      pending.each {|p| log p }

      requires 'migrated db'.with('.', env)
    end
  }
end

dep 'deployed assets precompiled', :old_id, :new_id, :env do
  setup {
    # If the branch was changed, git supplies 0000000 for old_id,
    # so the commit range is 'everything'.
    effective_old_id = old_id[/^0+$/] ? '' : old_id
    pending = shell(
      "git diff --numstat #{effective_old_id}..#{new_id}"
    ).split("\n").grep(
      /^[\d\s]+app\/assets\//
    )
    if pending.empty?
      log "No assets were changed."
    else
      log "#{pending.length} assets#{'s' unless pending.length == 1} changed:"
      pending.each {|p| log p }

      requires 'assets precompiled'.with(env)
    end
  }
end

dep 'assets precompiled', :env, :template => 'task' do
  run {
    shell "bundle exec rake assets:precompile RAILS_ENV=#{env}"
  }
end
