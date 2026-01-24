#![allow(unexpected_cfgs)]
mod frb_generated; /* AUTO INJECTED BY flutter_rust_bridge. This line may not be accurate, and you can change it according to your needs. */
mod crypto;

use std::fs;
use std::path::Path;

#[no_mangle]
#[cfg(target_os = "ios")]
pub extern "C" fn dummy_method_to_enforce_bundling() {
    // 正确的 FRB 符号签名和补全
    extern "C" {
        fn frb_get_rust_content_hash() -> u64;
        fn store_dart_post_cobject(ptr: *const std::ffi::c_void);
        fn frb_init_frb_dart_api_dl(api_dl_data: *mut std::ffi::c_void) -> isize;
    }
    
    unsafe {
        // 使用 black_box 防止编译器优化掉这些引用
        std::hint::black_box(frb_get_rust_content_hash as usize);
        std::hint::black_box(store_dart_post_cobject as usize);
        std::hint::black_box(frb_init_frb_dart_api_dl as usize);
    }
}

// 导出文件类型枚举以供Dart使用
#[frb(sync)]
pub fn get_file_type_generic() -> u8 { FileType::Generic as u8 }

#[frb(sync)]
pub fn get_file_type_image() -> u8 { FileType::Image as u8 }

#[frb(sync)]
pub fn get_file_type_novel() -> u8 { FileType::Novel as u8 }

#[frb(sync)]
pub fn get_file_type_other() -> u8 { FileType::Other as u8 }

#[frb(sync)]
pub fn get_file_type_comic() -> u8 { FileType::Comic as u8 }

#[frb(sync)]
pub fn get_file_type_rich_novel() -> u8 { FileType::RichNovel as u8 }

// 获取文件类型描述
#[frb(sync)]
pub fn get_file_type_description(file_type: u8) -> String {
    let ft = match file_type {
        0 => FileType::Generic,
        1 => FileType::Image,
        2 => FileType::Novel,
        3 => FileType::Comic,
        4 => FileType::RichNovel,
        _ => FileType::Other,
    };
    crypto::get_file_type_description(ft).to_string()
}

use flutter_rust_bridge::frb;
use crate::crypto::FileType;
use std::sync::Once;

static INIT: Once = Once::new();

// 初始化函数，用于设置日志等
fn init_once() {
    INIT.call_once(|| {
        // 可以在这里添加日志初始化等
    });
}

/// 加密文件 (异步)
/// 
/// 将明文数据加密为 .mxenc 格式
pub fn encrypt_file(
    plaintext: Vec<u8>,
    password: String,
    original_filename: String,
) -> Result<Vec<u8>, String> {
    init_once();
    
    match crypto::MxEncFile::encrypt(&plaintext, &password, &original_filename) {
        Ok(data) => Ok(data),
        Err(e) => Err(e.to_string()),
    }
}

pub fn encrypt_file_with_metadata(
    plaintext: Vec<u8>,
    password: String,
    original_filename: String,
    file_type: u8,
    metadata: Option<Vec<u8>>,
) -> Result<Vec<u8>, String> {
    init_once();
    
    let ft = match file_type {
        0 => FileType::Generic,
        1 => FileType::Image,
        2 => FileType::Novel,
        3 => FileType::Comic,
        4 => FileType::RichNovel,
        _ => FileType::Other,
    };
    match crypto::MxEncFile::encrypt_with_metadata(
        &plaintext,
        &password,
        &original_filename,
        ft,
        metadata.as_deref(),
    ) {
        Ok(data) => Ok(data),
        Err(e) => Err(e.to_string()),
    }
}

/// 通过路径加密文件 (异步，避免Dart端内存压力)
pub fn encrypt_file_by_path(
    input_path: String,
    output_path: String,
    password: String,
    original_filename: Option<String>,
    file_type: u8,
    metadata: Option<Vec<u8>>,
) -> Result<(), String> {
    init_once();
    
    // 在Rust后台线程读取文件
    let plaintext = fs::read(&input_path).map_err(|e| format!("读取文件失败: {}", e))?;
    
    // 确定原始文件名
    let filename = if let Some(name) = original_filename {
        name
    } else {
        Path::new(&input_path)
            .file_name()
            .and_then(|n| n.to_str())
            .unwrap_or("unknown")
            .to_string()
    };

    let ft = match file_type {
        0 => FileType::Generic,
        1 => FileType::Image,
        2 => FileType::Novel,
        3 => FileType::Comic,
        4 => FileType::RichNovel,
        _ => FileType::Other,
    };

    let encrypted = crypto::MxEncFile::encrypt_with_metadata(
        &plaintext,
        &password,
        &filename,
        ft,
        metadata.as_deref(),
    ).map_err(|e| e.to_string())?;

    fs::write(&output_path, encrypted).map_err(|e| format!("写入文件失败: {}", e))?;
    Ok(())
}

/// 解密文件 (异步)
/// 
/// 解密 .mxenc 格式的数据，返回原始文件名和明文数据
pub fn decrypt_file(
    mxenc_data: Vec<u8>,
    password: String,
) -> Result<(String, Vec<u8>), String> {
    init_once();
    
    match crypto::MxEncFile::decrypt(&mxenc_data, &password) {
        Ok((filename, data)) => Ok((filename, data)),
        Err(e) => Err(e.to_string()),
    }
}

/// 通过路径读取并解密文件，返回内容 (异步，避免Dart端读取文件)
pub fn decrypt_file_in_memory_by_path(
    input_path: String,
    password: String,
) -> Result<(String, Vec<u8>), String> {
    init_once();
    
    let mxenc_data = fs::read(&input_path).map_err(|e| format!("读取文件失败: {}", e))?;
    
    match crypto::MxEncFile::decrypt(&mxenc_data, &password) {
        Ok((filename, data)) => Ok((filename, data)),
        Err(e) => Err(e.to_string()),
    }
}

/// 解析 .mxenc 文件头
/// 
/// 仅解析文件头，获取原始文件名，不需要密码
#[frb(sync)]
pub fn parse_mxenc_header(mxenc_data: Vec<u8>) -> Result<String, String> {
    init_once();
    
    match crypto::MxEncFile::parse_header(&mxenc_data) {
        Ok(filename) => Ok(filename),
        Err(e) => Err(e.to_string()),
    }
}

/// 通过路径解析文件头 (异步，避免Dart端读取)
pub fn parse_mxenc_header_by_path(input_path: String) -> Result<(String, u8), String> {
    init_once();
    
    // 只读取头部，不需要读取整个文件
    // 这里简单起见先读一部分，或者为了复用 parse_header_extended，我们需要一个 reader 接口
    // 但 MxEncFile::parse_header_extended 接受 slice
    // 我们可以只读前 4KB，通常足够了
    
    use std::io::Read;
    let mut file = fs::File::open(&input_path).map_err(|e| format!("打开文件失败: {}", e))?;
    let mut buffer = vec![0u8; 4096]; // 4KB should be enough for header
    let n = file.read(&mut buffer).map_err(|e| format!("读取文件头失败: {}", e))?;
    buffer.truncate(n);
    
    match crypto::MxEncFile::parse_header_extended(&buffer) {
        Ok((filename, file_type)) => Ok((filename, file_type as u8)),
        Err(e) => Err(e.to_string()),
    }
}

#[frb(sync)]
pub fn parse_mxenc_header_extended(mxenc_data: Vec<u8>) -> Result<(String, u8), String> {
    init_once();
    
    match crypto::MxEncFile::parse_header_extended(&mxenc_data) {
        Ok((filename, file_type)) => Ok((filename, file_type as u8)),
        Err(e) => Err(e.to_string()),
    }
}

#[frb(sync)]
pub fn parse_mxenc_full_header(mxenc_data: Vec<u8>) -> Result<(String, u8, Vec<u8>), String> {
    init_once();
    
    match crypto::MxEncFile::parse_full_header(&mxenc_data) {
        Ok((filename, file_type, metadata)) => Ok((filename, file_type as u8, metadata)),
        Err(e) => Err(e.to_string()),
    }
}

/// 通过路径解析完整头部 (异步)
pub fn parse_mxenc_full_header_by_path(input_path: String) -> Result<(String, u8, Vec<u8>), String> {
    init_once();
    
    // 需要读取足够多的数据以包含 metadata
    // 这里我们保守一点，读取前 1MB，如果 metadata 很大可能不够，但目前设计 metadata < 64KB
    // 所以 1MB 足够了
    
    use std::io::Read;
    let mut file = fs::File::open(&input_path).map_err(|e| format!("打开文件失败: {}", e))?;
    let mut buffer = vec![0u8; 1024 * 1024]; // 1MB
    let n = file.read(&mut buffer).map_err(|e| format!("读取文件头失败: {}", e))?;
    buffer.truncate(n);
    
    match crypto::MxEncFile::parse_full_header(&buffer) {
        Ok((filename, file_type, metadata)) => Ok((filename, file_type as u8, metadata)),
        Err(e) => Err(e.to_string()),
    }
}


/// 生成设备指纹
/// 
/// 用于水印标识
#[frb(sync)]
pub fn generate_device_fingerprint() -> String {
    init_once();
    
    crypto::generate_device_fingerprint()
}

#[derive(Clone, Debug)]
pub enum ProgressPhase { ReadHeader, DeriveKey, Decrypt, Decode, Done }

#[derive(Clone, Debug)]
pub struct ProgressEvent { 
    pub phase: ProgressPhase, 
    pub percent: f32, 
    pub label: String,
    pub filename: Option<String>,
    pub data: Option<Vec<u8>>,
}

#[frb]
pub fn decrypt_file_with_progress(
    mxenc_data: Vec<u8>,
    password: String,
    sink: crate::frb_generated::StreamSink<ProgressEvent>,
) -> Result<(), String> {
    init_once();
    let _ = sink.add(ProgressEvent { 
        phase: ProgressPhase::ReadHeader, 
        percent: 0.05, 
        label: "读取文件".to_string(),
        filename: None,
        data: None 
    });
    let _ = sink.add(ProgressEvent { 
        phase: ProgressPhase::ReadHeader, 
        percent: 0.10, 
        label: "解析头部".to_string(),
        filename: None,
        data: None
    });
    let _ = sink.add(ProgressEvent { 
        phase: ProgressPhase::DeriveKey, 
        percent: 0.20, 
        label: "派生密钥".to_string(),
        filename: None,
        data: None
    });
    let _ = sink.add(ProgressEvent { 
        phase: ProgressPhase::Decrypt, 
        percent: 0.90, 
        label: "解密中".to_string(),
        filename: None,
        data: None
    });
    
    let (filename, data) = match crypto::MxEncFile::decrypt(&mxenc_data, &password) {
        Ok(res) => res,
        Err(e) => return Err(e.to_string()),
    };
    
    let _ = sink.add(ProgressEvent { 
        phase: ProgressPhase::Decode, 
        percent: 0.98, 
        label: "解码中".to_string(),
        filename: None,
        data: None
    });
    let _ = sink.add(ProgressEvent { 
        phase: ProgressPhase::Done, 
        percent: 1.00, 
        label: "完成".to_string(),
        filename: Some(filename),
        data: Some(data),
    });
    Ok(())
}

/// 通过路径解密并返回进度 (异步)
#[frb]
pub fn decrypt_file_by_path_with_progress(
    input_path: String,
    password: String,
    sink: crate::frb_generated::StreamSink<ProgressEvent>,
) -> Result<(), String> {
    init_once();
    let _ = sink.add(ProgressEvent { 
        phase: ProgressPhase::ReadHeader, 
        percent: 0.05, 
        label: "读取文件".to_string(),
        filename: None,
        data: None
    });
    
    let mxenc_data = fs::read(&input_path).map_err(|e| format!("读取文件失败: {}", e))?;
    
    let _ = sink.add(ProgressEvent { 
        phase: ProgressPhase::ReadHeader, 
        percent: 0.10, 
        label: "解析头部".to_string(),
        filename: None,
        data: None
    });
    let _ = sink.add(ProgressEvent { 
        phase: ProgressPhase::DeriveKey, 
        percent: 0.20, 
        label: "派生密钥".to_string(),
        filename: None,
        data: None
    });
    let _ = sink.add(ProgressEvent { 
        phase: ProgressPhase::Decrypt, 
        percent: 0.90, 
        label: "解密中".to_string(),
        filename: None,
        data: None
    });
    
    match crypto::MxEncFile::decrypt(&mxenc_data, &password) {
        Ok((filename, data)) => {
             let _ = sink.add(ProgressEvent { 
                 phase: ProgressPhase::Decode, 
                 percent: 0.98, 
                 label: "解码中".to_string(),
                 filename: None,
                 data: None
             });
             
             let _ = sink.add(ProgressEvent { 
                 phase: ProgressPhase::Done, 
                 percent: 1.00, 
                 label: "完成".to_string(),
                 filename: Some(filename),
                 data: Some(data),
             });
             Ok(())
        },
        Err(e) => Err(e.to_string()),
    }
}
