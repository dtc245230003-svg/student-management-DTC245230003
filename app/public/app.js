// Hỏi xác nhận trước khi xóa (không dùng script inline để tương thích CSP)
document.addEventListener('submit', function (e) {
  var msg = e.target.getAttribute('data-confirm');
  if (msg && !window.confirm(msg)) e.preventDefault();
});
