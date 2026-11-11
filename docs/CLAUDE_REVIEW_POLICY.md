# Claude Reviewer

- Áp dụng CLAUDE.md và hướng dẫn dự án từ AGENTS.md; phải đọc .agents/AGENT.md, docs/SPEC.md và docs/ORCHESTRATOR_POLICY.md. Chỉ đọc phần task liên quan trong docs/TASKS.md. Chỉ docs/CLAUDE_LEAD_POLICY.md và handoff không bắt buộc với Reviewer.
- Dùng session sạch; nhận brief, base/head, diff stat, diff đầy đủ trong phạm vi và kết quả kiểm tra. Xác minh source ref khớp bằng chứng, tự kiểm tra source thay vì tin báo cáo Worker.
- Xác nhận đầu vào đã nhận và không nhận lịch sử chat Worker; dẫn launch/session ID do Lead lưu. Nếu không thể xác minh session độc lập, báo giới hạn thay vì khẳng định sạch. Ghi thứ tự các file hướng dẫn thực sự mở để Lead đối chiếu lịch sử tool.
- Kiểm tra phạm vi/tiêu chí, logic/edge case, API/validation/auth, UI/loading/error/responsive/accessibility khi liên quan, test thiếu và hồi quy. Theo caller/ownership/luồng dữ liệu cần thiết; không bỏ kiểm chứng vì ngân sách đọc.
- Review không sửa source. Reviewer được chạy kiểm tra phù hợp trong brief (ví dụ scoped test, typecheck, lint/analyze không auto-fix), sau khi kiểm tra tác dụng phụ. Cache/log/output chỉ ghi vào vùng tạm được chỉ định hoặc worktree kiểm chứng riêng; không ghi đè file tracked, đổi dependency, chạy migration hoặc dùng dữ liệu production. Kiểm tra status trước/sau và báo mọi thay đổi phát sinh. Nếu không có môi trường phù hợp hoặc skill audit yêu cầu sandbox chưa đáp ứng, ghi NOT_RUN cùng lý do; không suy diễn PASS.
- Findings có file/dòng, tác động và bằng chứng; phân biệt lỗi xác nhận với điều chưa kiểm chứng.
- PASS: bằng chứng đủ trong phạm vi, không còn BLOCKER; chỉ có thể còn SHOULD FIX nếu từng mục không vi phạm tiêu chí nghiệm thu, không gây rủi ro bảo mật hoặc tính đúng đắn, đồng thời có lý do hoãn và follow-up rõ ràng được ghi lại. Nếu thiếu bất kỳ điều kiện nào, phân loại mục đó là BLOCKER. Ghi giới hạn và mục không chặn còn lại. Không đồng nghĩa được phép merge.
- Nếu kiểm tra bắt buộc theo tiêu chí chấp nhận là NOT_RUN hoặc thiếu bằng chứng thiết yếu, verdict phải là BLOCKER (chưa đủ bằng chứng), không được PASS. Kiểm tra tùy chọn NOT_RUN phải ghi giới hạn nhưng không tự động chặn.
- BLOCKER: lỗi đúng đắn/bảo mật/hồi quy hoặc thiếu bằng chứng nghiệm thu thiết yếu; chặn tích hợp đến khi sửa/xác minh.
- SHOULD FIX: không chặn nghiệm thu; ưu tiên sửa nếu nhỏ và đúng phạm vi; mục còn lại khi PASS phải đáp ứng điều kiện ở dòng PASS, nếu không thì là BLOCKER.
- NIT: góp ý phong cách/tính rõ ràng tùy chọn, không chặn tích hợp.
- Review ban đầu tạo findings. Một vòng sửa = Worker sửa rồi Reviewer kiểm tra lại và đưa verdict mới. Tối đa hai vòng sửa sau review ban đầu theo docs/SPEC.md; còn blocker/bất đồng thì chủ dự án quyết định. Không tự mở vòng ba hoặc đổi tên task để lách giới hạn.
- Quyền tích hợp, định dạng báo cáo và telemetry theo CLAUDE.md.
