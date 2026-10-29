(function () {
    "use strict";
    function initialize() {
        var pdfButton = document.getElementById('sports-toggle-pdf');
        var pdfPanel = document.getElementById('sports-pdf-panel');
        var pdfLabel = document.getElementById('sports-pdf-button-label');
        if (pdfButton && pdfPanel) {
            pdfButton.addEventListener('click', function () {
                var open = pdfPanel.hidden;
                pdfPanel.hidden = !open;
                pdfButton.setAttribute('aria-expanded', String(open));
                if (pdfLabel) pdfLabel.textContent = open ? 'إخفاء الإعلان' : 'عرض إعلان اليوم الرياضي';
            });
        }
        document.querySelectorAll('.sports-id-thumb img').forEach(function (image) {
            function showMissingFile() {
                image.hidden = true;
                if (image.dataset.unavailable) return;
                image.dataset.unavailable = "true";
                var note = document.createElement('span');
                note.className = 'sports-note';
                note.textContent = 'تعذر تحميل الصورة المسجلة. اضغط لفتح مرفقات الموظف.';
                image.after(note);
            }
            image.addEventListener('error', showMissingFile);
            if (image.complete && image.naturalWidth === 0) showMissingFile();
        });
        var container = document.getElementById("sports-selected-preview");
        if (!container) return;
        [1, 2].forEach(function (side) {
            var itemId = "P115_ATTACH" + side;
            var input = document.getElementById(itemId);
            if (!input || input.type !== "file") {
                input = document.querySelector("#" + itemId + " input[type=file],input[type=file][name='" + itemId + "'],#" + itemId + "_input");
            }
            if (!input) return;
            var objectUrl;
            input.addEventListener("change", function () {
                var old = document.getElementById("sports-preview-" + side);
                if (old) old.remove();
                if (objectUrl) URL.revokeObjectURL(objectUrl);
                objectUrl = null;
                input.setCustomValidity("");
                var file = input.files && input.files[0];
                if (!file) return;
                if (!["image/jpeg", "image/png"].includes(file.type) || file.size > 5242880 || file.size === 0) {
                    input.setCustomValidity("اختر صورة JPEG أو PNG بحد أقصى 5 ميجابايت.");
                    input.reportValidity();
                    return;
                }
                var preview = document.createElement("div");
                preview.id = "sports-preview-" + side;
                preview.className = "sports-id-thumb";
                var img = document.createElement("img");
                img.alt = side === 1 ? "معاينة وجه البطاقة قبل الحفظ" : "معاينة ظهر البطاقة قبل الحفظ";
                objectUrl = URL.createObjectURL(file);
                img.src = objectUrl;
                var caption = document.createElement("span");
                caption.textContent = img.alt;
                preview.append(img, caption);
                container.append(preview);
            });
        });
    }
    if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", initialize);
    else initialize();
}());
