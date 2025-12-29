var path = require('path');

exports.assetRoot = path.resolve(__dirname, '..');
exports.outputDir = path.resolve(__dirname, 'compiled');
exports.layout = 'single-page';
exports.title = 'lua_cliargs';
exports.scrollSpying = true;
exports.resizableSidebar = false;
exports.collapsibleSidebar = true;

exports.plugins = [
  require('tinydoc-plugin-lua')({
    source: 'src/**/*.lua'
  }),

  require('tinydoc-theme-gitbooks')()
];
