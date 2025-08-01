project(
    'dev.geopjr.Tuba',
    ['c', 'vala'],
    version: '0.9.2',
    meson_version: '>= 0.60.0',
    default_options: [
        'warning_level=2',
        'werror=false',
    ],
)

# add_project_arguments(['--define=USE_LISTVIEW'], language: 'vala')

# https://gitlab.gnome.org/GNOME/vala/-/issues/1413#note_1707480
if meson.get_compiler ('c').get_id () == 'clang'
  add_project_arguments('-Wno-incompatible-function-pointer-types', language: 'c')
endif

devel = get_option('devel')
distro = get_option('distro')

# Setup configuration file
config = configuration_data()
config.set('EXEC_NAME', meson.project_name())
config.set('GETTEXT_PACKAGE', meson.project_name())
config.set('BINDIR', join_paths(get_option('prefix'), get_option('bindir')))
config.set('LOCALEDIR', join_paths(get_option('prefix'), get_option('localedir')))
config.set('DOMAIN', meson.project_name ())
config.set('G_LOG_DOMAIN', 'Tuba')
config.set('RESOURCES', '/' + '/'.join(meson.project_name().split('.')) + '/')
config.set('VERSION', meson.project_version())
config.set('PREFIX', get_option('prefix'))
config.set('NAME', 'Tuba')
config.set('WEBSITE', 'https://github.com/GeopJr/Tuba')
config.set('DONATE_WEBSITE', 'https://geopjr.dev/donate')
config.set('TRANSLATE_WEBSITE', 'https://hosted.weblate.org/engage/tuba/')
config.set('WIKI_WEBSITE', 'https://github.com/GeopJr/Tuba/wiki')
config.set('PROFILE', devel ? 'development' : 'production')

if devel
  git = find_program('git')
  if git.found()
    branch = run_command('git', 'branch', '--show-current', check: true).stdout().strip()
    revision = run_command('git', 'rev-parse', '--short', 'HEAD', check: true).stdout().strip()
    version = '@0@-@1@'.format(branch, revision)
    config.set('VERSION', version)
  endif
endif

devmode = false
if devmode
  add_project_arguments(['--define=DEV_MODE'], language: 'vala')
endif

if host_machine.system() == 'windows'
  add_project_arguments(['--define=WINDOWS'], language: 'vala')
elif host_machine.system() == 'darwin'
  add_project_arguments(['--define=DARWIN'], language: 'vala')
endif

add_project_arguments(['--vapidir=' + meson.project_source_root() / 'vapi'], language: 'vala')
add_project_arguments (
  '-DGETTEXT_PACKAGE="@0@"'.format(meson.project_name()),
  '-DG_LOG_DOMAIN="Tuba"',
  '-w',
  language: 'c'
)

gnome = import('gnome')
i18n = import('i18n')

gstreamer = false
webkit = false
gexiv2 = false
gtk_dep = dependency('gtk4', version: '>=4.18', required: true)
libadwaita_dep = dependency('libadwaita-1', version: '>=1.7', required: true)
gtksourceview_dep = dependency('gtksourceview-5', required: true, version: '>=5.6.0')
libwebp_dep = dependency('libwebp', required: false)
libspelling = dependency('libspelling-1', required: get_option('spelling'))
clapper_dep = dependency('clapper-0.0', required: get_option('clapper'), version: '>=0.8.0')
clapper_gtk_dep = dependency('clapper-gtk-0.0', required: get_option('clapper'))
gstreamer_dep = dependency('gstreamer-1.0', required: get_option('gstreamer'))
webkit_dep = dependency('webkitgtk-6.0', required: get_option('in-app-browser'))

gexiv2_dep = dependency('gexiv2-0.16', version: '>=0.15', required: false)
if not gexiv2_dep.found ()
  gexiv2_dep = dependency('gexiv2', version: '>=0.14', required: get_option('gexiv2'))
endif

if not libwebp_dep.found ()
  warning('WebP support might be missing, please install webp-pixbuf-loader.')
endif

if libspelling.found ()
  add_project_arguments(['--define=LIBSPELLING'], language: 'vala')
endif

if libadwaita_dep.version().version_compare('>=1.7.5')
  add_project_arguments(['--define=ADW_1_7_5'], language: 'vala')
endif

if gtksourceview_dep.version().version_compare('>=5.7.1')
  add_project_arguments(['--define=GTKSOURCEVIEW_5_7_1'], language: 'vala')
endif

if gstreamer_dep.found ()
  add_project_arguments(['--define=GSTREAMER'], language: 'vala')
  gstreamer = true
endif

if gexiv2_dep.found ()
  add_project_arguments(['--define=GEXIV2'], language: 'vala')
  gexiv2 = true
endif

if clapper_dep.found () and clapper_gtk_dep.found ()
  add_project_arguments(['--define=CLAPPER'], language: 'vala')
  if (clapper_dep.get_variable('features').split().contains('mpris'))
    add_project_arguments(['--define=CLAPPER_MPRIS'], language: 'vala')
  endif
endif

if webkit_dep.found ()
  add_project_arguments(['--define=WEBKIT'], language: 'vala')
  webkit = true
endif

if gtk_dep.version().version_compare('>=4.19.1')
  add_project_arguments(['--define=GTK_4_19_1'], language: 'vala')
endif

if meson.get_compiler('vala').version().version_compare('>=0.56.19')
  add_project_arguments(['--define=VALAC_05619'], language: 'vala')
endif

sources = files()
subdir('src')

final_deps = [
  dependency('glib-2.0', version: '>=2.80.0'),
  dependency('gee-0.8', version: '>=0.8.5'),
  dependency('libsoup-3.0'),
  dependency('json-glib-1.0', version: '>=1.4.4'),
  dependency('libxml-2.0'),
  dependency('libsecret-1', required: true),
  dependency('icu-uc'),
  libspelling,
  gtksourceview_dep,
  gtk_dep,
  libadwaita_dep,
  meson.get_compiler('c').find_library('m', required: false),
  clapper_dep,
  clapper_gtk_dep,
  gstreamer_dep,
  webkit_dep,
  gexiv2_dep
]

subdir('data')
asresources = gnome.compile_resources(
    'as-resources',
    gresource_file,
    source_dir: 'data',
    c_name: 'as',
)

executable(
    meson.project_name(),
    asresources,
    sources,
    dependencies: final_deps,
    install: true,
    win_subsystem: 'windows'
)

subdir('tests')
subdir('po')

# Distributions use their own tooling (e.g. postinst, triggers, etc)
# so it is okay if the post_install() is not run on distro builds
if not distro
  # gnome.post_install() is available since meson 0.59.0
  if meson.version().version_compare('>=0.59.0')
    gnome.post_install(
      glib_compile_schemas: true,
      gtk_update_icon_cache: true,
      update_desktop_database: true,
    )
  else
    meson.add_install_script('build-aux/meson_post_install.py')
  endif
endif

if host_machine.system() == 'windows'
  configure_file(
      input : 'build-aux/dev.geopjr.Tuba.nsi.in',
      output : 'dev.geopjr.Tuba.nsi',
      configuration : config
  )
endif
