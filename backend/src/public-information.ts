import { Application } from 'express';

const escape = (value: string) => value.replace(/[&<>"']/g, ch => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[ch]!));

/** Public HTML works without Flutter, a login, or cookies (including review crawlers). */
export function servePublicInformation(app: Application): void {
  const operator = process.env.PRIVACY_OPERATOR_NAME?.trim() || '';
  const email = process.env.SUPPORT_EMAIL?.trim() || '';
  const configured = !!operator && /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email);
  const contact = configured
    ? `<p>Đơn vị/cá nhân vận hành: ${escape(operator)}. Liên hệ: <a href="mailto:${escape(email)}">${escape(email)}</a>.</p>`
    : '<p role="alert">BẢN NHÁP: Chưa xác nhận tên người vận hành và email hỗ trợ. Chưa dùng trang này để phát hành hoặc nộp xét duyệt.</p>';
  const pages: Record<string, [string, string]> = {
    '/privacy': ['Chính sách quyền riêng tư', `
      ${contact}
      <h2>Dữ liệu SignVoice xử lý</h2>
      <p>Khi đăng nhập bằng Facebook hoặc Google, SignVoice nhận mã định danh tài khoản, tên và email nếu nhà cung cấp trả về. Đăng nhập bằng email sử dụng email, tên và mật khẩu được băm. Hệ thống lưu hồ sơ, cài đặt, phiên đăng nhập và dữ liệu hội thoại/mục yêu thích khi bạn sử dụng chức năng lưu trên server.</p>
      <h2>Mục đích và bên xử lý</h2>
      <p>Dữ liệu được dùng để xác thực, cung cấp chức năng và bảo vệ tài khoản. Dữ liệu ứng dụng được lưu trong MongoDB Atlas. Google và Meta xử lý đăng nhập theo chính sách của họ. Khi truy cập qua Conveyor, lưu lượng đi qua dịch vụ tunnel Conveyor.</p>
      <h2>Camera và microphone</h2>
      <p>Ứng dụng yêu cầu quyền khi bạn sử dụng chức năng tương ứng. Khung hình camera được gửi tới dịch vụ AI của SignVoice để suy luận. Giọng nói được xử lý qua dịch vụ nhận dạng của trình duyệt/thiết bị và có thể được gửi tới nhà cung cấp dịch vụ đó. Bản triển khai này không chủ động lưu bản ghi âm hoặc video camera; văn bản bạn chọn lưu có thể được giữ trong dữ liệu hội thoại.</p>
      <h2>Cookie, nhật ký và thời gian lưu</h2>
      <p>Cookie phiên và OAuth hỗ trợ đăng nhập. Tài khoản và dữ liệu đã lưu được giữ cho tới khi bạn yêu cầu xóa. Nhật ký vận hành có thể chứa địa chỉ IP, trình duyệt và thời điểm truy cập; tùy cấu hình ghi log, một số dữ liệu yêu cầu có thể xuất hiện trong nhật ký. Bản sao lưu do người vận hành cấu hình có thể còn dữ liệu sau khi xóa trên hệ thống đang hoạt động; chính sách lưu trữ bản sao lưu cần được người vận hành xác nhận trước khi phát hành.</p>
      <h2>Quyền và xóa dữ liệu</h2>
      <p>Bạn có thể từ chối quyền camera/microphone, đăng xuất hoặc <a href="/data-deletion">xóa tài khoản và dữ liệu</a>. Việc xóa tài khoản SignVoice không xóa tài khoản Facebook/Google của bạn. Bạn có thể liên hệ người vận hành để hỏi về dữ liệu hoặc yêu cầu hỗ trợ.</p>`],
    '/data-deletion': ['Xóa tài khoản và dữ liệu', `
      ${contact}
      <h2>Xóa trực tiếp trong SignVoice</h2>
      <ol><li><a href="/#S05">Mở SignVoice</a> và đăng nhập tài khoản cần xóa.</li><li>Vào Cá nhân → Quyền riêng tư → Xóa tài khoản.</li><li>Đọc thông báo và xác nhận xóa vĩnh viễn.</li></ol>
      <p>Sau khi thành công, hồ sơ (kể cả ID Facebook/Google), cài đặt, phiên đăng nhập, hội thoại, mục yêu thích, lịch sử tra cứu và nhật ký tài khoản liên quan được xóa khỏi database đang hoạt động. Phiên đăng nhập cũ không thể sử dụng tiếp.</p>
      <p>Nội dung từ điển công khai mà nhân sự đã tạo không tự bị xóa theo tài khoản. Nhật ký vận hành dạng file và bản sao lưu không thuộc giao dịch xóa database; liên hệ người vận hành về việc xử lý các bản sao đó. Không có cam kết thời hạn xóa bản sao lưu cho tới khi người vận hành xác nhận cấu hình lưu trữ.</p>
      <h2>Nếu không đăng nhập được</h2><p>Liên hệ email hỗ trợ ở trên, cho biết tên tài khoản và phương thức đăng nhập. Người vận hành cần xác minh quyền sở hữu trước khi xử lý. Không gửi mật khẩu, mã OTP hoặc access token.</p>
      <p>Bạn cũng có thể gỡ quyền SignVoice trong phần cài đặt ứng dụng và trang web của Facebook. Gỡ quyền trên Facebook không tự xóa dữ liệu SignVoice; hãy dùng một trong các cách ở trên.</p>`],
  };
  for (const [route, [title, content]] of Object.entries(pages)) {
    app.get(route, (_req, res) => {
      res.setHeader('Cache-Control', 'no-store');
      res.status(configured ? 200 : 503).type('html').send(`<!doctype html><html lang="vi"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>${title} · SignVoice</title><style>body{font:18px/1.65 system-ui,sans-serif;color:#162337;background:#f4f7fb;margin:0}main{max-width:820px;margin:32px auto;padding:32px;background:white;border-radius:16px}a{color:#145ac4}h1{line-height:1.2}h2{font-size:1.25em;margin-top:28px}[role=alert]{padding:16px;background:#fff0cd}nav{display:flex;gap:20px;flex-wrap:wrap}@media(max-width:600px){main{margin:0;padding:22px;border-radius:0}}</style><main><nav><a href="/">SignVoice</a><a href="/privacy">Quyền riêng tư</a><a href="/data-deletion">Xóa dữ liệu</a></nav><h1>${title}</h1>${content}</main></html>`);
    });
  }
}
