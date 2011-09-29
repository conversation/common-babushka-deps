dep 'migrated db', :root, :env do
  requires 'app bundled', 'db gem'
  requires var(:data_required).starts_with?('y') ? 'existing data'.with : 'existing db'
  def orm
    grep('dm-rails', root/'Gemfile') ? :datamapper : :activerecord
  end
  setup {
    requires "migrated #{orm} db".with(root)

    if (db_config = yaml(root / 'config/database.yml')[env]).nil?
      log_error "There's no database.yml entry for the #{env} environment."
    else
      set :db_name, db_config['database']
    end
  }
end

dep 'migrated datamapper db', :template => 'task' do
  run {
    bundle_rake "db:migrate db:autoupgrade db:seed"
  }
end

dep 'migrated activerecord db', :root do
  met? {
    current_version = bundle_rake("db:version") {|shell| shell.stdout.val_for('Current version') }
    latest_version = Dir[
      root / 'db/migrate/*.rb'
    ].map {|f| File.basename f }.push('0').sort.last.split('_', 2).first

    (current_version.gsub(/^0+/, '') == latest_version.gsub(/^0+/, '')).tap {|result|
      unless current_version.blank?
        if latest_version == '0'
          log "This app doesn't have any migrations yet."
        elsif result
          log_ok "DB is up to date at migration #{current_version}"
        else
          log "DB needs migrating from #{current_version} to #{latest_version}"
        end
      end
    }
  }
  meet { bundle_rake "db:migrate --trace" }
end
