#![allow(unexpected_cfgs)]
mod frb_generated; /* AUTO INJECTED BY flutter_rust_bridge. This line may not be accurate, and you can change it according to your needs. */
pub mod crypto;

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

/// 加密文件
/// 
/// 将明文数据加密为 .mxenc 格式
#[frb(sync)]
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

#[frb(sync)]
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

/// 解密文件
/// 
/// 解密 .mxenc 格式的数据，返回原始文件名和明文数据
#[frb(sync)]
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
pub struct ProgressEvent { pub phase: ProgressPhase, pub percent: f32, pub label: String }

#[frb]
pub fn decrypt_file_with_progress(
    mxenc_data: Vec<u8>,
    password: String,
    sink: frb_generated::StreamSink<ProgressEvent>,
) -> Result<(), String> {
    init_once();
    let _ = sink.add(ProgressEvent { phase: ProgressPhase::ReadHeader, percent: 0.05, label: "读取文件".to_string() });
    let _ = sink.add(ProgressEvent { phase: ProgressPhase::ReadHeader, percent: 0.10, label: "解析头部".to_string() });
    let _ = sink.add(ProgressEvent { phase: ProgressPhase::DeriveKey, percent: 0.20, label: "派生密钥".to_string() });
    let _ = sink.add(ProgressEvent { phase: ProgressPhase::Decrypt, percent: 0.90, label: "解密中".to_string() });
    let _ = match crypto::MxEncFile::decrypt(&mxenc_data, &password) {
        Ok(_) => (),
        Err(e) => return Err(e.to_string()),
    };
    let _ = sink.add(ProgressEvent { phase: ProgressPhase::Decode, percent: 0.98, label: "解码中".to_string() });
    let _ = sink.add(ProgressEvent { phase: ProgressPhase::Done, percent: 1.00, label: "完成".to_string() });
    Ok(())
}
