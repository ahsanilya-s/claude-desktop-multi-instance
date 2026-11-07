// Adds a Copy button to each code block.
document.querySelectorAll('pre').forEach(function (pre) {
  var code = pre.querySelector('code');
  if (!code || !navigator.clipboard) return;
  var button = document.createElement('button');
  button.type = 'button';
  button.className = 'copy';
  button.textContent = 'Copy';
  button.addEventListener('click', function () {
    navigator.clipboard.writeText(code.innerText).then(function () {
      button.textContent = 'Copied';
      setTimeout(function () { button.textContent = 'Copy'; }, 1500);
    }, function () {
      button.textContent = 'Select and copy';
    });
  });
  pre.appendChild(button);
});
