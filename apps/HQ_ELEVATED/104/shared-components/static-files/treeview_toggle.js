(function () {
  apex.jQuery(function () {
    if (window.apex && window.apex.server && window.apex.server.process) {
      var originalProcess = apex.server.process;
      apex.server.process = function (processName, requestData, options) {
        if (processName === 'theme_roller' && requestData && requestData.x01 === 'get_styles') {
          var originalSuccess = options && options.success;
          if (options) {
            options.success = function (styles) {
              if (Array.isArray(styles)) {
                styles.forEach(function (style) {
                  if (style && style.id != null) style.id = String(style.id);
                });
              }
              if (originalSuccess) originalSuccess(styles);
            };
          }
        }
        return originalProcess.call(this, processName, requestData, options);
      };
    }

    apex.jQuery(document).on('click', '.a-TreeView-content', function (event) {
      var content = apex.jQuery(this);
      if (!apex.jQuery(event.target).closest('a').length) {
        var toggle = content.closest('li').find('.a-TreeView-toggle').first();
        if (toggle && toggle.length) toggle.trigger('click');
      }
    });
  });
}());
