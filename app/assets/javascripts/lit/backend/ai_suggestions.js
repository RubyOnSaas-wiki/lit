$(document).ready(function () {
  if ($.fn.select2) {
    $('.js-tag-filter').select2({ allowClear: true, width: '100%' });
  }

  $(document).on('click', '.js-edit-suggestion', function (event) {
    event.preventDefault();
    var row = $(this).closest('.ai-row');
    row.find('.ai-value').toggleClass('hidden');
    row.find('.ai-edit').toggleClass('hidden');
  });
});
